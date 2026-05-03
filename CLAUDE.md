# betterlint — Repo-Kontext

> **Onboarding-Handshake:** Lies in dieser Reihenfolge:
>
> 1. [`Projects/CLAUDE.md`](https://git.mon.k8b.co/) (globale Standards)
> 2. [`chameleon-ci/CLAUDE.md`](https://git.mon.k8b.co/chameleon-ci/) (Toolchain-Kontext, Konsumenten-API)
> 3. Diese Datei (betterlint-spezifisches)

---

## Was ist `betterlint`?

`betterlint` ist das All-in-One-Linter-Image der chameleon-ci-Toolchain. Statt MegaLinters >1 GB-Footprint (mit zig Lintern, die TCW gar nicht braucht) liefert `betterlint` ein kompaktes Alpine-Node-Image (~300 MB), in dem genau die Linter installiert sind, die in unseren Pipelines tatsächlich laufen: hadolint für Dockerfiles, tflint für OpenTofu, shellcheck für Shell-Skripte, markdownlint für Doku, commitlint für Conventional-Commits-Disziplin, spectral für OpenAPI/AsyncAPI und gherkin-official für BDD-Feature-Files.

Das Repo ist gleichzeitig der **Single-Source-of-Truth für Linter-Versionen in der gesamten TCW-Welt**. Wenn ein Vertical eine andere hadolint-Version braucht, ist das ein Indikator, dass entweder das Vertical falsch liegt oder die Toolchain einen Bump fällig hat. Drift wird in `betterlint` aufgelöst, nicht in einzelnen Konsumenten-Repos.

### Konsumenten

Alle Konsumenten-Verticals der TCW-Welt nutzen `betterlint` im Lint-Job ihrer `.forgejo/workflows/ci.yml`:

```yaml
lint:
  runs-on: ubuntu-22.04
  container:
    image: tcwlab/betterlint:1.0.0
  steps:
    - uses: https://data.forgejo.org/actions/checkout@v4
    - run: betterlint --dir .
```

Konkret eingebunden in: alle `Atrium/*`, `Spectrum/*`, `Tally/*`, `IdentServ/*`, `K8Box/*`, `IzyPhlirt/*`, `Testiversum/*`, `Sutagil/*`, plus die anderen `chameleon-ci/*`-Repos (cross-eating-our-own-dogfood: `opentofu`, `buildx`, `trivy`, `semantic-release` werden alle von `betterlint` selbst gelintet).

---

## Was ist drin?

Der Image-Inhalt — exakt wie im [Dockerfile](https://git.mon.k8b.co/chameleon-ci/betterlint/src/branch/main/Dockerfile) deklariert:

| Tool | Version | Quelle | Aufgabe |
| ---- | ------- | ------ | ------- |
| `hadolint` | `2.14.0` | GitHub-Release-Binary, arch-aware | Dockerfile-Lint |
| `tflint` | `0.62.0` | GitHub-Release-Binary, arch-aware | OpenTofu/Terraform-Lint |
| `shellcheck` | via apk (alpine 3.23) | Alpine-Paket | Shell-Skript-Lint |
| `markdownlint-cli2` | `0.22.1` | npm global | Markdown-Lint |
| `@commitlint/cli` | `20.x` | npm global | Conventional-Commits-Validator |
| `@commitlint/config-conventional` | `20.x` | npm global | Standard-Regelset |
| `@stoplight/spectral-cli` | `6.15.1` | npm global | OpenAPI/AsyncAPI-Lint |
| `gherkin-official` | `39.0.0` | pip3 (`--break-system-packages`) | Gherkin-Syntax-Validator |

Plus der zentrale Wrapper [`betterlint.sh`](https://git.mon.k8b.co/chameleon-ci/betterlint/src/branch/main/betterlint.sh) als `/usr/local/bin/betterlint`. Auto-Detect-Logik: betrachtet das Workdir und führt nur die Linter aus, deren Datei-Patterns matchen. Optionen: `--skip TOOL,...`, `--only TOOL,...`, `--dir PATH`, `--markdown` (für PR-Kommentar-Output), `--version`.

Base-Image: `node:24-alpine` als BUILDPLATFORM-aware Multi-Stage-Build. Das Image wird für `linux/amd64` und `linux/arm64` gebaut.

User: non-root `linter`-User. Workdir: `/workspace` (Konventionen-konform für Forgejo-Container-Jobs).

---

## Tool-Versionen und Pinning-Strategie

Jede Tool-Version ist als `ARG <TOOL>_VERSION=<x.y.z>` im Dockerfile fest eingebrannt. Build-Args im CI-Workflow überschreiben den Default und stellen sicher, dass Tag-Push und Image-Inhalt deckungsgleich sind.

### Updates

Heute manuell, weil chameleon-ci noch zu klein für Renovate ist. Workflow:

1. Im PR den `ARG <TOOL>_VERSION`-Default bumpen.
2. Smoke-Test im Build-Job (im Dockerfile letzte Stufe ist eine Smoke-Test-Section).
3. Conventional-Commits-Message: `feat: bump <tool> to <version>`.
4. semantic-release erzeugt neue `betterlint`-SemVer, pusht nach `tcwlab/betterlint:<x.y.z>`.
5. [`chameleon-ci/versions.yaml`](https://git.mon.k8b.co/chameleon-ci/) im Top-Level-Workspace aktualisieren.

Bei kleinen Tool-Updates (z.B. tflint-Patch): Patch-Bump der `betterlint`-SemVer. Bei Tool-Major-Updates oder neuem Tool: Minor-Bump.

### Disziplin

Niemals `latest` als Source-Pin verwenden. Jede Linter-Binary muss reproduzierbar in einem konkreten Tag landen, sonst ist „CI war grün" wertlos.

---

## Release-Verfahren

[`semantic-release`](https://git.mon.k8b.co/chameleon-ci/betterlint/src/branch/main/.releaserc) ist konfiguriert mit:

- `@semantic-release/commit-analyzer` → SemVer-Schritt aus Conventional-Commits ableiten
- `@semantic-release/release-notes-generator` → Changelog
- `@saithodev/semantic-release-gitea` → Forgejo-Release + Tag
- `@semantic-release/git` → Tag/Changelog committen

Tag-Schema: `v<x.y.z>`, Docker-Hub-Tag: `tcwlab/betterlint:<x.y.z>` plus rolling `latest`. Die zwei Tags werden im Publish-Job parallel gepusht (Multi-Arch via Buildx).

Auf `main` ist Branch-Protection aktiv (Status-Check `ci`, Squash-Merge, Branch-Delete-after-Merge). Alle Änderungen über PR von `claude/<slug>`-Branches.

---

## Was bei Versions-Bump zu tun ist

1. **PR auf `claude/bump-<tool>-<version>`**: `ARG <TOOL>_VERSION` ändern.
2. **Smoke-Tests laufen lassen** — der Smoke-Test-Block im Dockerfile prüft `<tool> --version`. Wenn der lokal/CI durch ist, ist die Binary kompatibel.
3. **Konsumenten-Pfade prüfen**: in den Templates ([`templates/iac-ci.yml`](https://git.mon.k8b.co/chameleon-ci/templates), [`templates/service-ci.yml`](https://git.mon.k8b.co/chameleon-ci/templates), [`templates/docker-image-ci.yml`](https://git.mon.k8b.co/chameleon-ci/templates)) ist `BETTERLINT_VERSION:` als Default gesetzt. Bei Major-Bump in `betterlint`: Templates separat anheben, damit neue Konsumenten-Repos den neuen Default kriegen.
4. **Changelog**: durch semantic-release automatisch — aber inhaltlich prüfen, ob die Commit-Message dem User klar macht, was sich geändert hat.
5. **Konsumenten-Outreach** (bei Breaking Changes): kurze Notiz in `chameleon-ci/CLAUDE.md` ergänzen, falls Konsumenten ihre `BETTERLINT_VERSION`-Werte hochziehen müssen.

---

## Was explizit NICHT in dieses Image gehört

- **Sprach-Compiler/Build-Tools** (Java, Go, Rust, Kotlin). `betterlint` ist Linter-Image, kein Build-Image. Build-Tools gehören in repo-eigene Build-Images oder in dedizierte chameleon-ci-Build-Images (z.B. `buildx`).
- **Vollständige Test-Runner** (junit, gotest, vitest). Tests laufen im Service-Container, nicht im Linter.
- **Heavy-Weight-Lints** (sonarqube-scanner, snyk-cli, prisma-cli). Wir bleiben bewusst leichtgewichtig.
- **Sprach-spezifische Code-Style-Linter** (eslint, prettier, ktlint, gofmt, rustfmt). Diese laufen im jeweiligen Repo-Container — `betterlint` macht nur sprachübergreifende Cross-Cutting-Lints.
- **Application-Security-Scanner** (Trivy, Grype, Snyk). Trivy hat ein eigenes `tcwlab/trivy`-Image — Sicherheitsscan und Lint sind klar getrennte CI-Phasen.

Wenn jemand fragt „kann hier nicht noch X rein?", ist die Default-Antwort **„Nein, baue ein eigenes Image."** Erst wenn drei oder mehr Verticals X im Lint-Job brauchen, wird ein Bump erwogen.

---

## Konsumenten-Snippets

### Standard-Lint-Job

```yaml
lint:
  name: Lint
  runs-on: ubuntu-22.04
  container:
    image: tcwlab/betterlint:1.0.0
  steps:
    - uses: https://data.forgejo.org/actions/checkout@v4
      with: { fetch-depth: 0 }
    - run: betterlint --dir .
```

### Selektiv (nur bestimmte Linter)

```yaml
- run: betterlint --only hadolint,shellcheck
- run: betterlint --skip commitlint,spectral
```

### Markdown-Output für PR-Kommentar

```yaml
- name: Lint mit Markdown-Report
  run: |
    set +e
    betterlint --dir . --markdown 2>&1 | tee /tmp/betterlint-report.md
    LINT_EXIT="${PIPESTATUS[0]}"
    exit "${LINT_EXIT}"
```

Den Report-Inhalt kann ein Folge-Step über die Forgejo-API als PR-Kommentar posten (Pattern existiert in den `chameleon-ci`-eigenen Image-Repos).

---

## Bekannte Schmerzpunkte / offene Themen

- **shellcheck via apk**: Version ist an Alpine 3.23 gekoppelt, nicht eigenständig pinnbar. Wenn ein Konsument eine konkrete shellcheck-Version braucht, muss das Image-Update über einen Alpine-Major-Bump gemacht werden.
- **gherkin-official via `--break-system-packages`**: ist Alpine-PEP-668-Workaround. Solange wir auf Alpine bleiben und keine venvs in einem Linter-Image verwenden wollen, bleibt das so. Acceptably ugly.
- **markdownlint-cli2 0.22.1** ist die in TCW konvergierte Version. Höhere Versionen haben Cross-Repo-Drift in `.markdownlint.json`-Schema verursacht — Bump erst nach koordinierter Konsumenten-Migration.
- **`commitlint`** Major-Updates erfordern oft Anpassung an `.commitlintrc.json` in den Konsumenten-Repos. Bei Major-Bump immer erst die Konsumenten-Tabelle in `chameleon-ci/CLAUDE.md` durchgehen.
- **Bootstrap-Problem**: betterlint kann sich selbst nicht linten (sonst Henne-Ei). Im eigenen `ci.yml` läuft Lint mit fixer Version-1.0.0-Image, nicht mit dem aktuellen Build-Output.
