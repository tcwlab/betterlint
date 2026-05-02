# tcwlab/betterlint

Kompaktes Multi-Linter-Image für CI-Pipelines. Enthält alle Linter, die TCW-Projekte brauchen — ohne die Schwergewichtigkeit von MegaLinter.

## Enthaltene Tools

| Tool | Version | Zweck |
|------|---------|-------|
| `shellcheck` | via apk | Shell-Script-Linting |
| `markdownlint-cli2` | 0.17.2 | Markdown-Linting |
| `@commitlint/cli` | 19.x | Conventional-Commits-Prüfung |
| `@commitlint/config-conventional` | 19.x | Commitlint-Config |
| `@stoplight/spectral-cli` | 6.x | OpenAPI-Linting |
| `gherkin-official` | 24–28 | Gherkin-Syntax-Validierung |

## Nutzung in Forgejo Actions

```yaml
jobs:
  lint:
    runs-on: ubuntu-22.04
    container:
      image: tcwlab/betterlint:1.0.0
    steps:
      - uses: https://data.forgejo.org/actions/checkout@v4

      - name: ShellCheck
        run: |
          find . -name '*.sh' -not -path './.git/*' \
            | xargs --no-run-if-empty shellcheck --severity=warning

      - name: Markdown
        run: markdownlint-cli2 --config .markdownlint.json "**/*.md" "#node_modules"

      - name: Conventional Commits
        run: |
          npx commitlint --config .commitlintrc.json \
            --from "${{ github.event.pull_request.base.sha }}" --to HEAD

      - name: OpenAPI
        run: spectral lint --ruleset .spectral.yaml docs/api/openapi.yaml

      - name: Gherkin
        run: |
          python3 - <<'PY'
          # ... (Gherkin-Parse-Skript)
          PY
```

## Versionierung

- Docker Hub: [tcwlab/betterlint](https://hub.docker.com/r/tcwlab/betterlint)
- Tags: `latest` + `x.y.z` (SemVer, eigene Versionsnummer da Multi-Tool-Image)

## Lokaler Build

```bash
docker build --build-arg BETTERLINT_VERSION=1.0.0 -t tcwlab/betterlint:1.0.0 .
```

## Lizenz

Apache 2.0 — The Chameleon Way
