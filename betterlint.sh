#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# betterlint — schlanke Multi-Linter-Alternative zu MegaLinter
#
# Erkennt automatisch, welche Dateitypen vorhanden sind, und führt nur die
# passenden Linter aus. Jeder Linter kann über --skip/--only oder Umgebungs-
# variablen gezielt ein- und ausgeschaltet werden.
#
# Unterstützte Tools:
#   shellcheck    .sh-Dateien
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
  shellcheck    Shell-Skripte (.sh)
  markdownlint  Markdown-Dateien (.md)
  commitlint    Git-Commit-Messages (braucht Konfigurationsdatei)
  spectral      OpenAPI / AsyncAPI (openapi*.yaml, asyncapi*.yaml)
  gherkin       Gherkin-Feature-Dateien (.feature)

Beispiele:
  betterlint
  betterlint --skip commitlint,spectral
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
declare -A DETAIL=()   # Fehlerdetails (max 300 Zeichen)
OVERALL_FAIL=false

set_result() {
    local name="$1" status="$2" detail="${3:-}"
    STATUS[$name]="$status"
    DETAIL[$name]="${detail:0:400}"
    [[ "$status" == "fail" ]] && OVERALL_FAIL=true
}

# ── Verzeichnis wechseln ─────────────────────────────────────────────────────
cd "$DIR"

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
        $ok && set_result shellcheck ok || set_result shellcheck fail "$out"
    fi
fi

# ── markdownlint ─────────────────────────────────────────────────────────────
if is_enabled markdownlint; then
    mapfile -t MD_FILES < <(find . -name "*.md" ! -path "./.git/*" 2>/dev/null || true)
    if [[ ${#MD_FILES[@]} -eq 0 ]]; then
        set_result markdownlint skip "keine .md-Dateien gefunden"
    else
        out=$(markdownlint-cli2 "**/*.md" "#node_modules" "#.git" 2>&1) \
            && set_result markdownlint ok \
            || set_result markdownlint fail "$out"
    fi
fi

# ── commitlint ───────────────────────────────────────────────────────────────
if is_enabled commitlint; then
    # Nur ausführen wenn Konfigurationsdatei vorhanden ist
    if ! find . -maxdepth 2 \( \
            -name ".commitlintrc*" -o \
            -name "commitlint.config.*" \) \
            ! -path "./.git/*" 2>/dev/null | grep -q .; then
        set_result commitlint skip "keine Konfigurationsdatei gefunden"
    elif ! command -v git &>/dev/null || ! git rev-parse HEAD &>/dev/null 2>&1; then
        set_result commitlint skip "kein Git-Repository"
    else
        out=$(git log -1 --pretty=%B 2>&1 | commitlint 2>&1) \
            && set_result commitlint ok \
            || set_result commitlint fail "$out"
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
        out=""; ok=true
        for f in "${API_FILES[@]}"; do
            r=$(spectral lint "$f" 2>&1) || { out+="$f: $r"$'\n'; ok=false; }
        done
        $ok && set_result spectral ok || set_result spectral fail "$out"
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
        $ok && set_result gherkin ok || set_result gherkin fail "$out"
    fi
fi

# ── Ausgabe ───────────────────────────────────────────────────────────────────
TOOLS=(shellcheck markdownlint commitlint spectral gherkin)

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

$OVERALL_FAIL && exit 1 || exit 0
