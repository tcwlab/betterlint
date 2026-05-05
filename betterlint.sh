#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# betterlint — compact multi-linter alternative to MegaLinter
#
# Auto-detects which file types are present and runs only the relevant
# linters. Each linter can be turned on/off with --skip/--only or via
# environment variables.
#
# Supported tools:
#   hadolint      Dockerfile linting              (report-only)
#   tflint        Terraform/OpenTofu files        (report-only)
#   ShellCheck    .sh files                       (report-only)
#   markdownlint  .md files                       (auto-fix via --fix)
#   commitlint    Git commit messages (only when a config is present)
#   spectral      OpenAPI / AsyncAPI (openapi*.yaml, asyncapi*.yaml)
#   gherkin       .feature files
#
# Auto-fix mode (--fix): runs auto-correctable formatters first, then the
# regular lint phase. All fixers below are bundled in the image:
#   markdownlint-cli2 --fix    Markdown
#   shfmt -w                   Bash / sh
#   prettier --write           JS/TS/JSON/CSS/SCSS/HTML
#                              (Markdown is left to markdownlint to avoid
#                              fix-loop conflicts; YAML is left to yamlfmt.)
#   eslint --fix               JS/TS (flat-config; baked-in default if the
#                              consumer repo ships no own config)
#   yamlfmt                    YAML
#
# Usage:
#   betterlint [--skip TOOL,...] [--only TOOL,...] [--dir PATH] [--fix] [--markdown]
#
# Environment variables (overridden by flags):
#   BETTERLINT_SKIP   Comma-separated list of tools to skip
#   BETTERLINT_ONLY   Run only these tools
#   BETTERLINT_DIR    Target directory (default: container's current working
#                     directory — typically /workspace because the image's
#                     WORKDIR is /workspace, but any `-w /work`, `-w /repo`,
#                     etc. works just as well).
#   BETTERLINT_FIX    Set to "1" to enable --fix mode
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

VERSION="${BETTERLINT_VERSION:-dev}"
# Default scan dir = container's current working directory. The image's
# WORKDIR is /workspace so naked `docker run` lands there, but `-w /work`,
# `-w /repo`, etc. work transparently — the script never assumes /workspace.
DIR="${BETTERLINT_DIR:-${PWD:-/workspace}}"
SKIP="${BETTERLINT_SKIP:-}"
ONLY="${BETTERLINT_ONLY:-}"
OUTPUT_MODE="text"
FIX_MODE="${BETTERLINT_FIX:-0}"

# Canonical set of linter / fixer names. Used for input validation in
# --only / --skip. The first seven are full lint tools (run in the lint
# phase + may also run in the fix phase); prettier/eslint/yamlfmt are
# fix-only — they only run when --fix is set, but they participate in the
# allow-/deny-list so users can do e.g. `--fix --skip eslint`.
KNOWN_TOOLS=(hadolint tflint shellcheck markdownlint commitlint spectral gherkin prettier eslint yamlfmt)

# Back-compat shim: with ENTRYPOINT ["/usr/local/bin/betterlint"], invocations
# like `docker run tcwlab/betterlint:1.0.0 betterlint --foo` would forward an
# extra "betterlint" arg into this script. Silently absorb it so old callers
# keep working without changes.
if [[ "${1:-}" == "betterlint" ]]; then shift; fi

# Back-compat shim (continued): legacy callers used `<TOOL>` as a positional
# arg to mean "run only this linter" — that pattern predates the explicit
# --only/--skip flags. If the first positional is a known linter name,
# convert to `--only TOOL` and emit a one-line deprecation warning so
# external pipelines (Atrium, Spectrum, …) keep working while we sweep their
# callers over to the explicit flag. Targeted (only KNOWN_TOOLS), so legit
# typos still hit the "Unknown option" arm below.
if [[ $# -gt 0 ]]; then
	for _kt in "${KNOWN_TOOLS[@]}"; do
		if [[ "$1" == "$_kt" ]]; then
			echo "betterlint: ⚠️  deprecated invocation: positional '$1' — use '--only $1' instead" >&2
			set -- --only "$1" "${@:2}"
			break
		fi
	done
fi

# Default config directory inside the image. The Dockerfile populates it
# via `COPY defaults/ /etc/betterlint/defaults/`. The BETTERLINT_DEFAULTS_DIR
# env var lets local tests redirect the path without patching the image.
DEFAULTS_DIR="${BETTERLINT_DEFAULTS_DIR:-/etc/betterlint/defaults}"

# ── Argument parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
	case "$1" in
	--skip)
		SKIP="$2"
		shift 2
		;;
	--only)
		ONLY="$2"
		shift 2
		;;
	--dir)
		DIR="$2"
		shift 2
		;;
	--markdown)
		OUTPUT_MODE="markdown"
		shift
		;;
	--fix)
		FIX_MODE="1"
		shift
		;;
	--version | -v)
		echo "betterlint ${VERSION}"
		exit 0
		;;
	--help | -h)
		cat <<'HELP'
betterlint — compact multi-linter alternative to MegaLinter

Usage:
  betterlint [OPTIONS]

Options:
  --skip TOOL,...   Skip these tools (comma-separated list)
  --only TOOL,...   Run only these tools (comma-separated list)
                    Note: --only and --skip are mutually exclusive.
  --dir  PATH       Target directory (default: current working directory,
                    typically /workspace via the image's WORKDIR but any
                    `-w /custom-mount` works without changes).
  --fix             Run auto-correctable linters in fix mode (in-place edits),
                    then run all linters as usual to report what's left.
  --markdown        Emit a Markdown table (for PR comments)
  --version         Print version
  --help            This help text

Available tools (use these exact names with --only / --skip):
  hadolint      Dockerfiles (Dockerfile*)              [report-only]
  tflint        Terraform/OpenTofu files (.tf)         [report-only]
  shellcheck    Shell scripts (.sh)                    [report-only]
  markdownlint  Markdown files (.md)                   [auto-fix supported]
  commitlint    Git commit messages (Conv. Commits)    [report-only]
  spectral      OpenAPI / AsyncAPI                     [report-only]
  gherkin       Gherkin feature files (.feature)      [report-only]
  prettier      JS/TS/JSON/CSS/SCSS/HTML formatter     [fix-only, --fix]
  eslint        JS/TS linter + auto-fixer              [fix-only, --fix]
  yamlfmt       YAML auto-formatter                    [fix-only, --fix]

Auto-fix tools (active only with --fix; all bundled in the image):
  markdownlint-cli2 --fix    in-place fix of *.md
  shfmt -w                   in-place format of *.sh
  prettier --write           JS/TS/JSON/CSS/SCSS/HTML
                             (Markdown left to markdownlint, YAML to yamlfmt)
  eslint --fix               JS/TS (flat-config default if consumer has none)
  yamlfmt                    YAML

  Tools without auto-fix support (hadolint, tflint, shellcheck, commitlint,
  spectral, gherkin) still run in --fix mode as plain linters and report
  remaining findings — exit code = max() over all phases.

Default configs:
  When the consumer repo ships no own configuration, betterlint falls
  back to the defaults baked into the image at /etc/betterlint/defaults/.
  Affected tools: markdownlint, commitlint, spectral, eslint. Existing
  consumer configs always win.

Selective invocation (the five common patterns):
  Run a single linter:        betterlint --only markdownlint
  Run a list of linters:      betterlint --only markdownlint,shellcheck
  Skip a single linter:       betterlint --skip hadolint
  Skip a list of linters:     betterlint --skip hadolint,tflint
  Combine selection + fix:    betterlint --fix --only markdownlint,shellcheck

Other examples:
  betterlint
  betterlint --fix
  betterlint --markdown > /tmp/lint-report.md
HELP
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		echo "Help: betterlint --help" >&2
		exit 1
		;;
	esac
done

# ── Argument validation ─────────────────────────────────────────────────────
# Exit code 2 = user-facing CLI error (distinct from exit 1 = lint findings).

# --only and --skip are mutually exclusive: combining them is logically
# inconsistent — either you allow-list or you deny-list, not both.
if [[ -n "$ONLY" && -n "$SKIP" ]]; then
	cat >&2 <<EOF
betterlint: --only and --skip are mutually exclusive.
  --only TOOL,...  defines an allow-list (everything else is skipped)
  --skip TOOL,...  defines a deny-list (everything else runs)
Pick exactly one.
EOF
	exit 2
fi

# Reject unknown linter names early so a typo in --only foo,markdownlint
# doesn't silently skip the linter the user actually wanted.
validate_tool_list() {
	local flag="$1" raw="$2"
	[[ -z "$raw" ]] && return 0
	local IFS=','
	# shellcheck disable=SC2206
	local entries=($raw)
	local entry known
	for entry in "${entries[@]}"; do
		# Trim surrounding whitespace
		entry="${entry#"${entry%%[![:space:]]*}"}"
		entry="${entry%"${entry##*[![:space:]]}"}"
		[[ -z "$entry" ]] && continue
		known=false
		for k in "${KNOWN_TOOLS[@]}"; do
			if [[ "$entry" == "$k" ]]; then
				known=true
				break
			fi
		done
		if ! $known; then
			{
				echo "betterlint: unknown linter '$entry' in $flag"
				echo "  Known linters: ${KNOWN_TOOLS[*]}"
				echo "  See 'betterlint --help' for the full list."
			} >&2
			exit 2
		fi
	done
}
validate_tool_list --only "$ONLY"
validate_tool_list --skip "$SKIP"

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

declare -A STATUS=() # ok | fail | skip
declare -A DETAIL=() # error detail (max 400 chars)
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

# ── Auto-fix phase ──────────────────────────────────────────────────────────
# Runs first when --fix is set. Each fixer is gated on:
#   1. is_enabled (respects --skip / --only)
#   2. command -v (skip with hint when the binary is missing)
#   3. file pattern match (skip silently when nothing matches)
# After the fix phase, the regular lint phase runs unchanged so the user gets
# a final report on remaining findings (incl. those that no auto-fixer can
# resolve, e.g. hadolint / tflint / shellcheck issues).
declare -A FIX_STATUS=() # ok | fail | skip | unavailable
declare -A FIX_DETAIL=()
FIX_FAIL=false

set_fix_result() {
	local name="$1" status="$2" detail="${3:-}"
	FIX_STATUS[$name]="$status"
	FIX_DETAIL[$name]="${detail:0:400}"
	if [[ "$status" == "fail" ]]; then FIX_FAIL=true; fi
}

if [[ "$FIX_MODE" == "1" ]]; then
	# --- markdownlint-cli2 --fix (Markdown) ---
	if is_enabled markdownlint; then
		mapfile -t MD_FILES_FIX < <(find . -name "*.md" ! -path "./.git/*" \
			! -path "./node_modules/*" 2>/dev/null || true)
		if [[ ${#MD_FILES_FIX[@]} -eq 0 ]]; then
			set_fix_result markdownlint-fix skip "no .md files found"
		elif ! command -v markdownlint-cli2 &>/dev/null; then
			set_fix_result markdownlint-fix unavailable "markdownlint-cli2 not on PATH"
		else
			markdownlint_cfg=(--config "${DEFAULTS_DIR}/markdownlint.json")
			for _cfg in .markdownlint-cli2.jsonc .markdownlint-cli2.yaml .markdownlint-cli2.cjs \
				.markdownlint-cli2.mjs .markdownlint.jsonc .markdownlint.json \
				.markdownlint.yaml .markdownlint.yml .markdownlint.cjs \
				.markdownlint.mjs .markdownlintrc; do
				if [[ -f "$_cfg" ]]; then
					markdownlint_cfg=()
					break
				fi
			done
			# markdownlint-cli2 --fix exits non-zero when issues remain after fixing;
			# that's expected and we don't treat the fix phase as failed for that.
			out=$(markdownlint-cli2 --fix "${markdownlint_cfg[@]}" \
				"**/*.md" "#node_modules" "#.git" 2>&1 || true)
			set_fix_result markdownlint-fix ok "${out:-no remaining issues}"
		fi
	fi

	# --- shfmt -w (Bash / sh) ---
	if is_enabled shellcheck; then
		mapfile -t SH_FILES_FIX < <(find . -name "*.sh" ! -path "./.git/*" \
			! -path "./node_modules/*" 2>/dev/null || true)
		if [[ ${#SH_FILES_FIX[@]} -eq 0 ]]; then
			set_fix_result shfmt skip "no .sh files found"
		elif ! command -v shfmt &>/dev/null; then
			set_fix_result shfmt unavailable "shfmt not on PATH (install via 'apk add shfmt')"
		else
			out=""
			ok=true
			for f in "${SH_FILES_FIX[@]}"; do
				r=$(shfmt -w "$f" 2>&1) || {
					out+="$f: $r"$'\n'
					ok=false
				}
			done
			if $ok; then set_fix_result shfmt ok; else set_fix_result shfmt fail "$out"; fi
		fi
	fi

	# --- prettier --write (JS/TS/JSON + CSS/SCSS + HTML) ---
	# Bundled in the image. Markdown and YAML are deliberately excluded:
	# markdownlint owns Markdown formatting (running both creates fix-loops
	# on heading/list whitespace), and yamlfmt owns YAML.
	if is_enabled prettier; then
		mapfile -t PRETTIER_FILES_FIX < <(find . \
			\( -name "*.js" -o -name "*.jsx" -o -name "*.mjs" -o -name "*.cjs" \
			-o -name "*.ts" -o -name "*.tsx" \
			-o -name "*.json" \
			-o -name "*.css" -o -name "*.scss" \
			-o -name "*.html" -o -name "*.htm" \) \
			! -path "./.git/*" ! -path "./node_modules/*" 2>/dev/null || true)
		if [[ ${#PRETTIER_FILES_FIX[@]} -eq 0 ]]; then
			set_fix_result prettier skip "no Prettier-eligible files found"
		elif ! command -v prettier &>/dev/null; then
			# Should never trigger in the official image; kept as a safety
			# net for local runs against a stripped-down environment.
			set_fix_result prettier unavailable "prettier not on PATH"
		else
			if out=$(prettier --write "${PRETTIER_FILES_FIX[@]}" 2>&1); then
				set_fix_result prettier ok "$out"
			else
				set_fix_result prettier fail "$out"
			fi
		fi
	fi

	# --- eslint --fix (JS/TS) ---
	# Bundled in the image. Falls back to the flat-config default at
	# ${DEFAULTS_DIR}/eslint.config.js when the consumer repo ships no
	# own config — same fallback pattern as markdownlint/commitlint/spectral.
	if is_enabled eslint; then
		mapfile -t ESLINT_FILES_FIX < <(find . \
			\( -name "*.js" -o -name "*.jsx" -o -name "*.mjs" -o -name "*.cjs" \
			-o -name "*.ts" -o -name "*.tsx" \) \
			! -path "./.git/*" ! -path "./node_modules/*" 2>/dev/null || true)
		if [[ ${#ESLINT_FILES_FIX[@]} -eq 0 ]]; then
			set_fix_result eslint skip "no JS/TS files found"
		elif ! command -v eslint &>/dev/null; then
			set_fix_result eslint unavailable "eslint not on PATH"
		else
			# Look for a consumer flat-config / legacy-config file. eslint v9
			# discovers these names automatically; we only point --config at
			# the baked-in default when none is found.
			eslint_cfg=(--config "${DEFAULTS_DIR}/eslint.config.js")
			for _cfg in eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts \
				.eslintrc.js .eslintrc.cjs .eslintrc.yaml .eslintrc.yml .eslintrc.json .eslintrc; do
				if [[ -f "$_cfg" ]]; then
					eslint_cfg=()
					break
				fi
			done
			# eslint exits non-zero on remaining lint errors; capture but don't fail
			# the fix phase on it — the lint phase below will surface them again.
			out=$(eslint --fix "${eslint_cfg[@]}" "${ESLINT_FILES_FIX[@]}" 2>&1 || true)
			set_fix_result eslint ok "${out:-no remaining issues}"
		fi
	fi

	# --- yamlfmt (YAML) ---
	# Bundled in the image. Default settings — yamlfmt picks up a consumer
	# `.yamlfmt` / `yamlfmt.yml` automatically when present, so no explicit
	# --config plumbing here.
	if is_enabled yamlfmt; then
		mapfile -t YAML_FILES_FIX < <(find . \
			\( -name "*.yaml" -o -name "*.yml" \) \
			! -path "./.git/*" ! -path "./node_modules/*" 2>/dev/null || true)
		if [[ ${#YAML_FILES_FIX[@]} -eq 0 ]]; then
			set_fix_result yamlfmt skip "no YAML files found"
		elif ! command -v yamlfmt &>/dev/null; then
			set_fix_result yamlfmt unavailable "yamlfmt not on PATH"
		else
			if out=$(yamlfmt "${YAML_FILES_FIX[@]}" 2>&1); then
				set_fix_result yamlfmt ok "$out"
			else
				set_fix_result yamlfmt fail "$out"
			fi
		fi
	fi
fi

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
			if [[ -f "$_cfg" ]]; then
				hadolint_cfg=(--config "$_cfg")
				break
			fi
		done
		out=""
		ok=true
		for f in "${DOCKER_FILES[@]}"; do
			r=$(hadolint "${hadolint_cfg[@]}" "$f" 2>&1) ||
				{
					out+="$f: $r"$'\n'
					ok=false
				}
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
		out=""
		ok=true
		for d in "${TF_DIRS[@]}"; do
			r=$(tflint --chdir "$d" 2>&1) || {
				out+="$d: $r"$'\n'
				ok=false
			}
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
		out=""
		ok=true
		for f in "${SH_FILES[@]}"; do
			r=$(shellcheck "$f" 2>&1) || {
				out+="$r"$'\n'
				ok=false
			}
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
			if [[ -f "$_cfg" ]]; then
				markdownlint_cfg=()
				break
			fi
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
			if [[ -f "$_cfg" ]]; then
				spectral_cfg=()
				break
			fi
		done
		out=""
		ok=true
		for f in "${API_FILES[@]}"; do
			r=$(spectral lint "${spectral_cfg[@]}" "$f" 2>&1) || {
				out+="$f: $r"$'\n'
				ok=false
			}
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
		out=""
		ok=true
		for f in "${FEAT_FILES[@]}"; do
			# Read the file path into a variable so we can use it safely inside the heredoc
			FEATURE_FILE="$f"
			r=$(
				python3 - <<PYEOF 2>&1
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
			) || {
				out+="${f}: $r"$'\n'
				ok=false
			}
		done
		if $ok; then set_result gherkin ok; else set_result gherkin fail "$out"; fi
	fi
fi

# ── Output ──────────────────────────────────────────────────────────────────
TOOLS=(hadolint tflint shellcheck markdownlint commitlint spectral gherkin)
FIXERS=(markdownlint-fix shfmt prettier eslint yamlfmt)

if [[ "$OUTPUT_MODE" == "markdown" ]]; then
	if $OVERALL_FAIL; then
		echo "**❌ Linting failed**"
	else
		echo "**✅ All linting checks passed**"
	fi
	echo ""
	if [[ "$FIX_MODE" == "1" ]]; then
		echo "### Auto-fix phase"
		echo ""
		echo "| Fixer | Status | Details |"
		echo "|---|---|---|"
		for t in "${FIXERS[@]}"; do
			s="${FIX_STATUS[$t]:-skip}"
			d="${FIX_DETAIL[$t]:-}"
			d="${d//|/,}"
			d="${d//$'\n'/ }"
			d="${d//\`/\'}"
			d=$(printf '%s' "$d" | sed 's/\x1b\[[0-9;]*m//g')
			case "$s" in
			ok) echo "| \`$t\` | 🛠️ fixed | ${d:0:200} |" ;;
			fail) echo "| \`$t\` | ❌ | \`${d:0:200}\` |" ;;
			skip) echo "| \`$t\` | ⏭️ | $d |" ;;
			unavailable) echo "| \`$t\` | ⚠️ | $d |" ;;
			esac
		done
		echo ""
		echo "### Lint phase"
		echo ""
	fi
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
		ok) echo "| \`$t\` | ✅ | |" ;;
		fail) echo "| \`$t\` | ❌ | \`${d:0:200}\` |" ;;
		skip) echo "| \`$t\` | ⏭️ | $d |" ;;
		esac
	done
else
	printf "\nbetterlint %s — %s\n\n" "$VERSION" "$(date -u '+%Y-%m-%d %H:%M UTC')"
	if [[ "$FIX_MODE" == "1" ]]; then
		echo "── Auto-fix phase ──"
		for t in "${FIXERS[@]}"; do
			s="${FIX_STATUS[$t]:-skip}"
			case "$s" in
			ok) printf "  🛠️  %-18s  fixed in-place\n" "$t" ;;
			fail) printf "  ❌  %-18s  FAILED\n" "$t" ;;
			skip) printf "  ⏭️   %-18s  (%s)\n" "$t" "${FIX_DETAIL[$t]:-}" ;;
			unavailable) printf "  ⚠️   %-18s  (%s)\n" "$t" "${FIX_DETAIL[$t]:-}" ;;
			esac
		done
		echo ""
		echo "── Lint phase ──"
	fi
	for t in "${TOOLS[@]}"; do
		s="${STATUS[$t]:-skip}"
		case "$s" in
		ok) printf "  ✅  %-16s\n" "$t" ;;
		fail) printf "  ❌  %-16s  FAILED\n" "$t" ;;
		skip) printf "  ⏭️   %-16s  (%s)\n" "$t" "${DETAIL[$t]:-}" ;;
		esac
	done

	# Print error details (fix phase first, then lint phase)
	if [[ "$FIX_MODE" == "1" ]]; then
		for t in "${FIXERS[@]}"; do
			if [[ "${FIX_STATUS[$t]:-}" == "fail" ]]; then
				printf "\n── fix: %s ──\n%s\n" "$t" "${FIX_DETAIL[$t]}"
			fi
		done
	fi
	for t in "${TOOLS[@]}"; do
		if [[ "${STATUS[$t]:-}" == "fail" ]]; then
			printf "\n── %s ──\n%s\n" "$t" "${DETAIL[$t]}"
		fi
	done
	echo ""
fi

# Exit code = max() over fix phase and lint phase. The lint phase always
# runs after fixers so remaining (non-auto-fixable) findings still surface.
if $OVERALL_FAIL || $FIX_FAIL; then exit 1; else exit 0; fi
