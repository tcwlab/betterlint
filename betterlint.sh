#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# betterlint — compact multi-linter alternative to MegaLinter
#
# Auto-detects which file types are present and runs only the relevant
# linters. Each linter can be turned on/off with --skip/--only or via
# environment variables.
#
# Supported tools:
#   hadolint      Dockerfile linting
#   tflint        Terraform/OpenTofu files
#   ShellCheck    .sh files
#   markdownlint  .md files
#   commitlint    Git commit messages (only when a config is present)
#   spectral      OpenAPI / AsyncAPI (openapi*.yaml, asyncapi*.yaml)
#   gherkin       .feature files
#
# Usage:
#   betterlint [--skip TOOL,...] [--only TOOL,...] [--dir PATH] [--markdown]
#
# Environment variables (overridden by flags):
#   BETTERLINT_SKIP   Comma-separated list of tools to skip
#   BETTERLINT_ONLY   Run only these tools
#   BETTERLINT_DIR    Target directory (default: /workspace)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

VERSION="${BETTERLINT_VERSION:-dev}"
DIR="${BETTERLINT_DIR:-/workspace}"
SKIP="${BETTERLINT_SKIP:-}"
ONLY="${BETTERLINT_ONLY:-}"
OUTPUT_MODE="text"

# Default config directory inside the image. The Dockerfile populates it
# via `COPY defaults/ /etc/betterlint/defaults/`. The BETTERLINT_DEFAULTS_DIR
# env var lets local tests redirect the path without patching the image.
DEFAULTS_DIR="${BETTERLINT_DEFAULTS_DIR:-/etc/betterlint/defaults}"

# ── Argument parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip)
            SKIP="$2"; shift 2 ;;
        --only)
            ONLY="$2"; shift 2 ;;
        --dir)
            DIR="$2"; shift 2 ;;
        --markdown)
            OUTPUT_MODE="markdown"; shift ;;
        --version|-v)
            echo "betterlint ${VERSION}"; exit 0 ;;
        --help|-h)
            cat <<'HELP'
betterlint — compact multi-linter alternative to MegaLinter

Usage:
  betterlint [OPTIONS]

Options:
  --skip TOOL,...   Skip these tools (comma-separated list)
  --only TOOL,...   Run only these tools (comma-separated list)
  --dir  PATH       Target directory (default: /workspace)
  --markdown        Emit a Markdown table (for PR comments)
  --version         Print version
  --help            This help text

Available tools:
  hadolint      Dockerfiles (Dockerfile*)
  tflint        Terraform/OpenTofu files (.tf)
  shellcheck    Shell scripts (.sh)
  markdownlint  Markdown files (.md)
  commitlint    Git commit messages (Conventional Commits 1.0)
  spectral      OpenAPI / AsyncAPI (openapi*.yaml, asyncapi*.yaml)
  gherkin       Gherkin feature files (.feature)

Default configs:
  When the consumer repo ships no own configuration, betterlint falls
  back to the defaults baked into the image at /etc/betterlint/defaults/.
  Affected tools: markdownlint, commitlint, spectral. Existing consumer
  configs always win.

Examples:
  betterlint
  betterlint --skip commitlint,spectral
  betterlint --only hadolint,tflint
  betterlint --only shellcheck,markdownlint
  betterlint --markdown > /tmp/lint-report.md
HELP
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Help: betterlint --help" >&2
            exit 1 ;;
    esac
done

# ── Helpers ─────────────────────────────────────────────────────────────────

is_enabled() {
    local t="$1"
    if [[ -n "$ONLY" ]]; then
        [[ ",$ONLY," == *",$t,"* ]]
        return
    fi
    if [[ -n "$SKIP" ]]; then
        [[ ",$SKIP," != *",$t,"* ]]
        return
    fi
    return 0
}

declare -A STATUS=()   # ok | fail | skip
declare -A DETAIL=()   # error detail (max 400 chars)
OVERALL_FAIL=false

set_result() {
    local name="$1" status="$2" detail="${3:-}"
    STATUS[$name]="$status"
    DETAIL[$name]="${detail:0:400}"
    # Use if/fi instead of && — prevents `set -e` from tripping when status != "fail"
    if [[ "$status" == "fail" ]]; then OVERALL_FAIL=true; fi
}

# ── Switch directory ────────────────────────────────────────────────────────
cd "$DIR"

# ── hadolint ────────────────────────────────────────────────────────────────
if is_enabled hadolint; then
    mapfile -t DOCKER_FILES < <(find . \( -name "Dockerfile" -o -name "Dockerfile.*" \) \
        ! -path "./.git/*" 2>/dev/null || true)
    if [[ ${#DOCKER_FILES[@]} -eq 0 ]]; then
        set_result hadolint skip "no Dockerfiles found"
    else
        # Pass the config file explicitly when present (depending on the
        # version, hadolint does not always discover it from the CWD).
        hadolint_cfg=()
        for _cfg in ".hadolint.yaml" ".hadolint.yml"; do
            if [[ -f "$_cfg" ]]; then hadolint_cfg=(--config "$_cfg"); break; fi
        done
        out=""; ok=true
        for f in "${DOCKER_FILES[@]}"; do
            r=$(hadolint "${hadolint_cfg[@]}" "$f" 2>&1) \
                || { out+="$f: $r"$'\n'; ok=false; }
        done
        if $ok; then set_result hadolint ok; else set_result hadolint fail "$out"; fi
    fi
fi

# ── tflint ──────────────────────────────────────────────────────────────────
if is_enabled tflint; then
    mapfile -t TF_DIRS < <(find . -name "*.tf" ! -path "./.git/*" \
        -exec dirname {} \; 2>/dev/null | sort -u || true)
    if [[ ${#TF_DIRS[@]} -eq 0 ]]; then
        set_result tflint skip "no .tf files found"
    else
        out=""; ok=true
        for d in "${TF_DIRS[@]}"; do
            r=$(tflint --chdir "$d" 2>&1) || { out+="$d: $r"$'\n'; ok=false; }
        done
        if $ok; then set_result tflint ok; else set_result tflint fail "$out"; fi
    fi
fi

# ── shellcheck ──────────────────────────────────────────────────────────────
if is_enabled shellcheck; then
    mapfile -t SH_FILES < <(find . -name "*.sh" ! -path "./.git/*" 2>/dev/null || true)
    if [[ ${#SH_FILES[@]} -eq 0 ]]; then
        set_result shellcheck skip "no .sh files found"
    else
        out=""; ok=true
        for f in "${SH_FILES[@]}"; do
            r=$(shellcheck "$f" 2>&1) || { out+="$r"$'\n'; ok=false; }
        done
        if $ok; then set_result shellcheck ok; else set_result shellcheck fail "$out"; fi
    fi
fi

# ── markdownlint ────────────────────────────────────────────────────────────
if is_enabled markdownlint; then
    mapfile -t MD_FILES < <(find . -name "*.md" ! -path "./.git/*" 2>/dev/null || true)
    if [[ ${#MD_FILES[@]} -eq 0 ]]; then
        set_result markdownlint skip "no .md files found"
    else
        # Look for a consumer config — when none is in the workdir, use
        # the default baked into the image, so repos without their own
        # markdownlint config no longer fail with ENOENT.
        # The list of file names must match the paths that
        # markdownlint-cli2 itself discovers.
        markdownlint_cfg=(--config "${DEFAULTS_DIR}/markdownlint.json")
        for _cfg in .markdownlint-cli2.jsonc .markdownlint-cli2.yaml .markdownlint-cli2.cjs \
                    .markdownlint-cli2.mjs .markdownlint.jsonc .markdownlint.json \
                    .markdownlint.yaml .markdownlint.yml .markdownlint.cjs \
                    .markdownlint.mjs .markdownlintrc; do
            if [[ -f "$_cfg" ]]; then markdownlint_cfg=(); break; fi
        done
        if out=$(markdownlint-cli2 "${markdownlint_cfg[@]}" "**/*.md" "#node_modules" "#.git" 2>&1); then
            set_result markdownlint ok
        else
            set_result markdownlint fail "$out"
        fi
    fi
fi

# ── commitlint ──────────────────────────────────────────────────────────────
if is_enabled commitlint; then
    if ! command -v git &>/dev/null || ! git rev-parse HEAD &>/dev/null 2>&1; then
        set_result commitlint skip "not a git repository"
    else
        # Look for a consumer config; fall back to the default so
        # Conventional Commits validation also fires in repos without
        # their own commitlint config.
        commitlint_cfg=(--config "${DEFAULTS_DIR}/commitlint.config.cjs")
        if find . -maxdepth 2 \( \
                -name ".commitlintrc*" -o \
                -name "commitlint.config.*" \) \
                ! -path "./.git/*" 2>/dev/null | grep -q .; then
            commitlint_cfg=()
        fi
        if out=$(git log -1 --pretty=%B 2>&1 | commitlint "${commitlint_cfg[@]}" 2>&1); then
            set_result commitlint ok
        else
            set_result commitlint fail "$out"
        fi
    fi
fi

# ── spectral ────────────────────────────────────────────────────────────────
if is_enabled spectral; then
    mapfile -t API_FILES < <(find . \
        \( -name "openapi*.yaml" -o -name "openapi*.yml" \
           -o -name "asyncapi*.yaml" -o -name "asyncapi*.yml" \) \
        ! -path "./.git/*" ! -path "./node_modules/*" 2>/dev/null || true)
    if [[ ${#API_FILES[@]} -eq 0 ]]; then
        set_result spectral skip "no OpenAPI/AsyncAPI files found"
    else
        # Look for a consumer ruleset; otherwise use the default baked
        # into the image (activates spectral:oas + spectral:asyncapi).
        spectral_cfg=(--ruleset "${DEFAULTS_DIR}/spectral.yaml")
        for _cfg in .spectral.yaml .spectral.yml .spectral.json .spectral.js; do
            if [[ -f "$_cfg" ]]; then spectral_cfg=(); break; fi
        done
        out=""; ok=true
        for f in "${API_FILES[@]}"; do
            r=$(spectral lint "${spectral_cfg[@]}" "$f" 2>&1) || { out+="$f: $r"$'\n'; ok=false; }
        done
        if $ok; then set_result spectral ok; else set_result spectral fail "$out"; fi
    fi
fi

# ── gherkin ─────────────────────────────────────────────────────────────────
if is_enabled gherkin; then
    mapfile -t FEAT_FILES < <(find . -name "*.feature" ! -path "./.git/*" 2>/dev/null || true)
    if [[ ${#FEAT_FILES[@]} -eq 0 ]]; then
        set_result gherkin skip "no .feature files found"
    else
        out=""; ok=true
        for f in "${FEAT_FILES[@]}"; do
            # Read the file path into a variable so we can use it safely inside the heredoc
            FEATURE_FILE="$f"
            r=$(python3 - <<PYEOF 2>&1
from gherkin.parser import Parser
from gherkin.token_scanner import TokenScanner
import sys
try:
    with open('${FEATURE_FILE}') as fh:
        Parser().parse(TokenScanner(fh.read()))
    print('ok')
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
PYEOF
            ) || { out+="${f}: $r"$'\n'; ok=false; }
        done
        if $ok; then set_result gherkin ok; else set_result gherkin fail "$out"; fi
    fi
fi

# ── Output ──────────────────────────────────────────────────────────────────
TOOLS=(hadolint tflint shellcheck markdownlint commitlint spectral gherkin)

if [[ "$OUTPUT_MODE" == "markdown" ]]; then
    if $OVERALL_FAIL; then
        echo "**❌ Linting failed**"
    else
        echo "**✅ All linting checks passed**"
    fi
    echo ""
    echo "| Tool | Status | Details |"
    echo "|---|---|---|"
    for t in "${TOOLS[@]}"; do
        s="${STATUS[$t]:-skip}"
        d="${DETAIL[$t]:-}"
        # Escape Markdown special characters
        d="${d//|/,}"
        d="${d//$'\n'/ }"
        d="${d//\`/\'}"
        # Strip ANSI codes
        d=$(printf '%s' "$d" | sed 's/\x1b\[[0-9;]*m//g')
        case "$s" in
            ok)   echo "| \`$t\` | ✅ | |" ;;
            fail) echo "| \`$t\` | ❌ | \`${d:0:200}\` |" ;;
            skip) echo "| \`$t\` | ⏭️ | $d |" ;;
        esac
    done
else
    printf "\nbetterlint %s — %s\n\n" "$VERSION" "$(date -u '+%Y-%m-%d %H:%M UTC')"
    for t in "${TOOLS[@]}"; do
        s="${STATUS[$t]:-skip}"
        case "$s" in
            ok)   printf "  ✅  %-16s\n" "$t" ;;
            fail) printf "  ❌  %-16s  FAILED\n" "$t" ;;
            skip) printf "  ⏭️   %-16s  (%s)\n" "$t" "${DETAIL[$t]:-}" ;;
        esac
    done

    # Print error details
    for t in "${TOOLS[@]}"; do
        if [[ "${STATUS[$t]:-}" == "fail" ]]; then
            printf "\n── %s ──\n%s\n" "$t" "${DETAIL[$t]}"
        fi
    done
    echo ""
fi

if $OVERALL_FAIL; then exit 1; else exit 0; fi
