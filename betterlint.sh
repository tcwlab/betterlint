#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# betterlint — schlanke Multi-Linter-Alternative zu MegaLinter
#
# Erkennt automatisch, welche Dateitypen vorhanden sind, und führt nur die
# passenden Linter aus. Jeder Linter kann über --skip/--only oder Umgebungs-
# variablen gezielt ein- und ausgeschaltet werden.
#
# Unterstützte Tools:
#   hadolint      Dockerfile-Linting
#   tflint        Terraform/OpenTofu-Dateien
#   ShellCheck    .sh-Dateien
#   markdownlint  .md-Dateien
#   commitlint    Git-Commit-Messages (nur wenn Konfiguration vorhanden)
#   spectral      OpenAPI / AsyncAPI (openapi*.yaml, asyncapi*.yaml)
#   gherkin       .feature-Dateien
#
# Usage:
#   betterlint [--skip TOOL,...] [--only TOOL,...] [--dir PATH] [--markdown]
#
# Umgebungsvariablen (werden durch Flags überschrieben):
#   BETTERLINT_SKIP   Kommagetrennte Tools zum Überspringen
#   BETTERLINT_ONLY   Nur diese Tools ausführen
#   BETTERLINT_DIR    Ziel-Verzeichnis (Standard: /workspace)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

VERSION="${BETTERLINT_VERSION:-dev}"
DIR="${BETTERLINT_DIR:-/workspace}"
SKIP="${BETTERLINT_SKIP:-}"
ONLY="${BETTERLINT_ONLY:-}"
OUTPUT_MODE="text"

# Default-Config-Verzeichnis im Image. Wird vom Dockerfile via
# `COPY defaults/ /etc/betterlint/defaults/` befüllt. Über die Env-Variable
# BETTERLINT_DEFAULTS_DIR kann der Pfad für lokale Tests umgebogen werden,
# ohne im Image herumzupatchen.
DEFAULTS_DIR="${BETTERLINT_DEFAULTS_DIR:-/etc/betterlint/defaults}"

# ── Argument-Parsing ─────────────────────────────────────────────────────────
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
betterlint — schlanke Multi-Linter-Alternative zu MegaLinter

Usage:
  betterlint [OPTIONS]

Optionen:
  --skip TOOL,...   Tools überspringen (Kommaliste)
  --only TOOL,...   Nur diese Tools ausführen (Kommaliste)
  --dir  PATH       Ziel-Verzeichnis (Standard: /workspace)
  --markdown        Ausgabe als Markdown-Tabelle (für PR-Beschreibungen)
  --version         Version ausgeben
  --help            Diese Hilfe

Verfügbare Tools:
  hadolint      Dockerfiles (Dockerfile*)
  tflint        Terraform/OpenTofu-Dateien (.tf)
  shellcheck    Shell-Skripte (.sh)
  markdownlint  Markdown-Dateien (.md)
  commitlint    Git-Commit-Messages (Conventional Commits 1.0)
  spectral      OpenAPI / AsyncAPI (openapi*.yaml, asyncapi*.yaml)
  gherkin       Gherkin-Feature-Dateien (.feature)

Default-Configs:
  Wenn das Konsumenten-Repo keine eigene Konfiguration mitbringt, greift
  betterlint auf die im Image gebackenen Defaults zurück
  (/etc/betterlint/defaults/). Betroffene Tools: markdownlint, commitlint,
  spectral. Vorhandene Konsumenten-Configs werden vorrangig benutzt.

Beispiele:
  betterlint
  betterlint --skip commitlint,spectral
  betterlint --only hadolint,tflint
  betterlint --only shellcheck,markdownlint
  betterlint --markdown > /tmp/lint-report.md
HELP
            exit 0 ;;
        *)
            echo "Unbekannte Option: $1" >&2
            echo "Hilfe: betterlint --help" >&2
            exit 1 ;;
    esac
done

# ── Hilfsfunktionen ──────────────────────────────────────────────────────────

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
declare -A DETAIL=()   # Fehlerdetails (max 400 Zeichen)
OVERALL_FAIL=false

set_result() {
    local name="$1" status="$2" detail="${3:-}"
    STATUS[$name]="$status"
    DETAIL[$name]="${detail:0:400}"
    # if/fi statt &&: verhindert, dass set -e greift wenn status != "fail"
    if [[ "$status" == "fail" ]]; then OVERALL_FAIL=true; fi
}

# ── Verzeichnis wechseln ─────────────────────────────────────────────────────
cd "$DIR"

# ── hadolint ─────────────────────────────────────────────────────────────────
if is_enabled hadolint; then
    mapfile -t DOCKER_FILES < <(find . \( -name "Dockerfile" -o -name "Dockerfile.*" \) \
        ! -path "./.git/*" 2>/dev/null || true)
    if [[ ${#DOCKER_FILES[@]} -eq 0 ]]; then
        set_result hadolint skip "keine Dockerfiles gefunden"
    else
        # Config-Datei explizit übergeben falls vorhanden (hadolint findet sie
        # je nach Version nicht immer automatisch aus dem CWD)
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

# ── tflint ───────────────────────────────────────────────────────────────────
if is_enabled tflint; then
    mapfile -t TF_DIRS < <(find . -name "*.tf" ! -path "./.git/*" \
        -exec dirname {} \; 2>/dev/null | sort -u || true)
    if [[ ${#TF_DIRS[@]} -eq 0 ]]; then
        set_result tflint skip "keine .tf-Dateien gefunden"
    else
        out=""; ok=true
        for d in "${TF_DIRS[@]}"; do
            r=$(tflint --chdir "$d" 2>&1) || { out+="$d: $r"$'\n'; ok=false; }
        done
        if $ok; then set_result tflint ok; else set_result tflint fail "$out"; fi
    fi
fi

# ── shellcheck ───────────────────────────────────────────────────────────────
if is_enabled shellcheck; then
    mapfile -t SH_FILES < <(find . -name "*.sh" ! -path "./.git/*" 2>/dev/null || true)
    if [[ ${#SH_FILES[@]} -eq 0 ]]; then
        set_result shellcheck skip "keine .sh-Dateien gefunden"
    else
        out=""; ok=true
        for f in "${SH_FILES[@]}"; do
            r=$(shellcheck "$f" 2>&1) || { out+="$r"$'\n'; ok=false; }
        done
        if $ok; then set_result shellcheck ok; else set_result shellcheck fail "$out"; fi
    fi
fi

# ── markdownlint ─────────────────────────────────────────────────────────────
if is_enabled markdownlint; then
    mapfile -t MD_FILES < <(find . -name "*.md" ! -path "./.git/*" 2>/dev/null || true)
    if [[ ${#MD_FILES[@]} -eq 0 ]]; then
        set_result markdownlint skip "keine .md-Dateien gefunden"
    else
        # Konsumenten-Config suchen — wenn keine im Workdir liegt, den
        # gebackenen Default aus dem Image nutzen, damit Repos ohne eigene
        # markdownlint-Config nicht mehr mit ENOENT scheitern.
        # Liste der Dateinamen muss mit den Pfaden übereinstimmen, die
        # markdownlint-cli2 selbst erkennt.
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

# ── commitlint ───────────────────────────────────────────────────────────────
if is_enabled commitlint; then
    if ! command -v git &>/dev/null || ! git rev-parse HEAD &>/dev/null 2>&1; then
        set_result commitlint skip "kein Git-Repository"
    else
        # Konsumenten-Config suchen; ohne Treffer Fallback nutzen, damit
        # Conventional-Commits-Validierung auch in Repos ohne eigene
        # commitlint-Config greift.
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

# ── spectral ─────────────────────────────────────────────────────────────────
if is_enabled spectral; then
    mapfile -t API_FILES < <(find . \
        \( -name "openapi*.yaml" -o -name "openapi*.yml" \
           -o -name "asyncapi*.yaml" -o -name "asyncapi*.yml" \) \
        ! -path "./.git/*" ! -path "./node_modules/*" 2>/dev/null || true)
    if [[ ${#API_FILES[@]} -eq 0 ]]; then
        set_result spectral skip "keine OpenAPI/AsyncAPI-Dateien gefunden"
    else
        # Konsumenten-Ruleset suchen; sonst gebackenen Default verwenden
        # (aktiviert spectral:oas + spectral:asyncapi).
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

# ── gherkin ──────────────────────────────────────────────────────────────────
if is_enabled gherkin; then
    mapfile -t FEAT_FILES < <(find . -name "*.feature" ! -path "./.git/*" 2>/dev/null || true)
    if [[ ${#FEAT_FILES[@]} -eq 0 ]]; then
        set_result gherkin skip "keine .feature-Dateien gefunden"
    else
        out=""; ok=true
        for f in "${FEAT_FILES[@]}"; do
            # Wir lesen den Dateipfad in eine Variable, um ihn sicher im heredoc zu nutzen
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

# ── Ausgabe ───────────────────────────────────────────────────────────────────
TOOLS=(hadolint tflint shellcheck markdownlint commitlint spectral gherkin)

if [[ "$OUTPUT_MODE" == "markdown" ]]; then
    if $OVERALL_FAIL; then
        echo "**❌ Linting fehlgeschlagen**"
    else
        echo "**✅ Alle Linting-Checks bestanden**"
    fi
    echo ""
    echo "| Tool | Status | Details |"
    echo "|---|---|---|"
    for t in "${TOOLS[@]}"; do
        s="${STATUS[$t]:-skip}"
        d="${DETAIL[$t]:-}"
        # Markdown-Sonderzeichen escapen
        d="${d//|/,}"
        d="${d//$'\n'/ }"
        d="${d//\`/\'}"
        # ANSI-Codes entfernen
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

    # Fehlerdetails ausgeben
    for t in "${TOOLS[@]}"; do
        if [[ "${STATUS[$t]:-}" == "fail" ]]; then
            printf "\n── %s ──\n%s\n" "$t" "${DETAIL[$t]}"
        fi
    done
    echo ""
fi

if $OVERALL_FAIL; then exit 1; else exit 0; fi
