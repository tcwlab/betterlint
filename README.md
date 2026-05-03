# tcwlab/betterlint

Kompaktes Multi-Linter-Image für CI-Pipelines. Enthält alle Linter, die TCW-Projekte brauchen —
ohne die Schwergewichtigkeit von MegaLinter. Der `betterlint`-Wrapper erkennt automatisch, welche
Dateitypen vorhanden sind, und führt nur die passenden Linter aus.

## Enthaltene Tools

| Tool | Version | Zweck |
| --- | --- | --- |
| `hadolint` | 2.14.0 | Dockerfile-Linting |
| `tflint` | 0.62.0 | Terraform/OpenTofu-Linting |
| `shellcheck` | via apk | Shell-Script-Linting |
| `markdownlint-cli2` | 0.22.1 | Markdown-Linting |
| `@commitlint/cli` | 20.x | Conventional-Commits-Prüfung |
| `@stoplight/spectral-cli` | 6.15.1 | OpenAPI/AsyncAPI-Linting |
| `gherkin-official` | 39.0.0 | Gherkin-Syntax-Validierung |
| `jq` | via apk | JSON-Processor (Validierung + Filter) |
| `yq` | via apk | YAML-Processor (Validierung + Filter) |

## Nutzung in Forgejo Actions

```yaml
jobs:
  betterlint-check:
    runs-on: ubuntu-22.04
    container:
      image: tcwlab/betterlint:latest
    steps:
      - uses: https://data.forgejo.org/actions/checkout@v4

      - name: Run betterlint
        run: |
          set +e
          betterlint --dir . --markdown 2>&1 | tee /tmp/betterlint-report.md
          LINT_EXIT="${PIPESTATUS[0]}"
          exit "${LINT_EXIT}"
```

### Optionen

| Flag | Beschreibung |
| --- | --- |
| `--skip TOOL,...` | Tools überspringen (Kommaliste) |
| `--only TOOL,...` | Nur diese Tools ausführen |
| `--dir PATH` | Ziel-Verzeichnis (Standard: `/workspace`) |
| `--markdown` | Ausgabe als Markdown-Tabelle |
| `--version` | Version ausgeben |

Alternativ über Umgebungsvariablen:

```bash
BETTERLINT_SKIP=commitlint,spectral betterlint --dir .
BETTERLINT_ONLY=hadolint,tflint    betterlint --dir .
```

## Versionierung

- Docker Hub: [tcwlab/betterlint](https://hub.docker.com/r/tcwlab/betterlint)
- Tags: `latest` + `x.y.z` (SemVer, automatisch per Semantic Release)

## Lokaler Build

```bash
docker build --build-arg BETTERLINT_VERSION=dev -t tcwlab/betterlint:dev .
```

## Lizenz

Apache 2.0 — The Chameleon Way
