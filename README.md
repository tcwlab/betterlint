# tcwlab/betterlint

> Compact multi-linter image for CI pipelines. Bundles every linter that TCW projects actually need (`hadolint`, `tflint`, `shellcheck`, `markdownlint`, `commitlint`, `spectral`, `gherkin`, plus `jq` and `yq`) into a single Alpine-based image with a smart auto-detect wrapper. Drop-in alternative to MegaLinter when you want a smaller, faster image with sensible defaults.

[![Docker Pulls](https://img.shields.io/docker/pulls/tcwlab/betterlint?label=pulls)](https://hub.docker.com/r/tcwlab/betterlint)
[![Image Size](https://img.shields.io/docker/image-size/tcwlab/betterlint/latest?label=size)](https://hub.docker.com/r/tcwlab/betterlint/tags)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

---

## Quick start

```bash
docker pull tcwlab/betterlint:latest

# Run against the current directory
docker run --rm -v "$PWD:/workspace" tcwlab/betterlint:latest
```

Or as a Forgejo / GitHub-Actions container job:

```yaml
lint:
  runs-on: ubuntu-22.04
  container:
    image: tcwlab/betterlint:latest
  steps:
    - uses: https://data.forgejo.org/actions/checkout@v4
    - run: betterlint --dir .
```

The wrapper auto-detects which file types are present and runs only the relevant linters — no configuration needed for the common case.

> Quick-start examples use `:latest` so you can try the image immediately. For
> production CI pipelines, pin a concrete tag — see [Tags](#tags) below.

---

## Tags

> Version numbers below are illustrative. For the current set of tags, see
> [Docker Hub tags](https://hub.docker.com/r/tcwlab/betterlint/tags).

| Tag | Description |
|-----|-------------|
| `1.0.0`, `1.0`, `1` | Concrete SemVer (recommended for production pipelines) |
| `latest` | Rolling reference; always points at the newest release |

**Always pin a concrete version in production.** `latest` is fine for local experiments, but pinning protects your pipeline from a toolchain bump that lands without a PR. The major/minor floating tags (`1`, `1.0`) are convenient for internal use; external consumers should pin the full SemVer.

The `betterlint` SemVer tracks the wrapper image as a whole, not any single bundled tool. When one of the underlying tools is bumped, the image typically takes a minor step.

---

## Supported architectures

- `linux/amd64`
- `linux/arm64`

Every tag is a multi-arch manifest list. Docker pulls the right architecture automatically.

---

## What's included

| Tool | Version | Purpose |
|------|---------|---------|
| [`hadolint`](https://github.com/hadolint/hadolint) | `2.14.0` | Dockerfile linting |
| [`tflint`](https://github.com/terraform-linters/tflint) | `0.62.0` | Terraform / OpenTofu linting |
| [`shellcheck`](https://www.shellcheck.net/) | from Alpine 3.23 apk | Shell script linting |
| [`markdownlint-cli2`](https://github.com/DavidAnson/markdownlint-cli2) | `0.22.1` | Markdown linting |
| [`@commitlint/cli`](https://commitlint.js.org/) | `20.x` | Conventional Commits validation |
| [`@commitlint/config-conventional`](https://commitlint.js.org/reference/configuration.html) | `20.x` | Default commitlint rule set |
| [`@stoplight/spectral-cli`](https://stoplight.io/open-source/spectral) | `6.15.1` | OpenAPI / AsyncAPI linting |
| [`gherkin-official`](https://pypi.org/project/gherkin-official/) | `39.0.0` | Gherkin/BDD `.feature` syntax validation |
| `jq` | from Alpine apk | JSON processor (validation + filter) |
| `yq` | from Alpine apk | YAML processor (validation + filter) |
| `betterlint` (wrapper) | `1.0.0` | Auto-detect runner (`/usr/local/bin/betterlint`) |

Base image: `node:24-alpine`. Default workdir: `/workspace`. Default user: `linter` (non-root, uid auto-assigned).

---

## Usage

### Run every relevant linter automatically

```bash
docker run --rm -v "$PWD:/workspace" tcwlab/betterlint:1.0.0
```

The wrapper inspects `/workspace`, picks the linters whose file patterns match, and skips the rest. Skipped linters appear in the report with a `⏭️` marker so you can see why nothing ran.

### Run only specific tools

```bash
docker run --rm -v "$PWD:/workspace" tcwlab/betterlint:1.0.0 \
  betterlint --only hadolint,shellcheck
```

### Skip specific tools

```bash
docker run --rm -v "$PWD:/workspace" tcwlab/betterlint:1.0.0 \
  betterlint --skip commitlint,spectral
```

### Generate a Markdown report (for PR comments)

```bash
docker run --rm -v "$PWD:/workspace" tcwlab/betterlint:1.0.0 \
  betterlint --markdown > lint-report.md
```

### Forgejo workflow — full snippet

```yaml
lint:
  runs-on: ubuntu-22.04
  container:
    image: tcwlab/betterlint:1.0.0
  steps:
    - uses: https://data.forgejo.org/actions/checkout@v4
    - name: Run betterlint
      run: |
        set +e
        betterlint --dir . --markdown 2>&1 | tee /tmp/betterlint-report.md
        LINT_EXIT="${PIPESTATUS[0]}"
        exit "${LINT_EXIT}"
```

### CLI options

| Flag | Description |
|------|-------------|
| `--skip TOOL,...` | Skip these tools (comma-separated list) |
| `--only TOOL,...` | Run only these tools (comma-separated list) |
| `--dir PATH`      | Target directory (default: `/workspace`) |
| `--markdown`      | Emit a Markdown table (suitable for PR comments) |
| `--version`       | Print the wrapper version and exit |
| `--help`          | Print the full help text |

Equivalent environment variables (overridden by CLI flags):

| Variable | Equivalent flag |
|----------|-----------------|
| `BETTERLINT_SKIP` | `--skip` |
| `BETTERLINT_ONLY` | `--only` |
| `BETTERLINT_DIR`  | `--dir` |

---

## Configuration

### Default configs baked into the image

If your repo has no own configuration file for `markdownlint`, `commitlint`, or `spectral`, the wrapper falls back to defaults shipped inside the image at `/etc/betterlint/defaults/`:

| Tool | Default config | Notes |
|------|----------------|-------|
| `markdownlint` | `/etc/betterlint/defaults/markdownlint.json` | `MD013` and `MD033` disabled |
| `commitlint`   | `/etc/betterlint/defaults/commitlint.config.cjs` | Conventional Commits 1.0, header max 100 chars |
| `spectral`     | `/etc/betterlint/defaults/spectral.yaml` | Activates `spectral:oas` + `spectral:asyncapi` |

A consumer config in the workdir always wins. The wrapper looks for the standard config locations (`.markdownlint*`, `.commitlintrc*`, `commitlint.config.*`, `.spectral.*`) and only falls back to the defaults when none is found.

To point the wrapper at a different defaults directory (useful for local tests):

```bash
docker run --rm -v "$PWD:/workspace" -v "$PWD/my-defaults:/opt/my-defaults" \
  -e BETTERLINT_DEFAULTS_DIR=/opt/my-defaults \
  tcwlab/betterlint:1.0.0
```

### Volume mount points

| Path | Purpose |
|------|---------|
| `/workspace` | Default workdir; mount your project here |
| `/etc/betterlint/defaults/` | Image-side default configs (read-only) |

### Detected file patterns

| Tool | Patterns |
|------|----------|
| `hadolint` | `Dockerfile`, `Dockerfile.*` |
| `tflint` | `*.tf` (per-directory) |
| `shellcheck` | `*.sh` |
| `markdownlint` | `*.md` |
| `commitlint` | latest `git log -1` (only when the workdir is a git repo) |
| `spectral` | `openapi*.yaml`, `openapi*.yml`, `asyncapi*.yaml`, `asyncapi*.yml` |
| `gherkin` | `*.feature` |

---

## Why `betterlint` and not MegaLinter?

[MegaLinter](https://github.com/oxsecurity/megalinter) is excellent and supports far more languages, but it ships in a >1 GB image with linters that TCW projects do not use. `betterlint` keeps the image around 300 MB by including only the linters that actually run in our pipelines, with deterministic auto-detect logic in a small Bash wrapper. Trade-off accepted: less coverage out of the box, faster pipelines and fewer moving parts.

If you need a linter that is not in this image, please open a [feature request](https://github.com/tcwlab/betterlint/issues) — once three or more consumers need the same tool, we evaluate adding it. Otherwise the recommendation is to run that linter in its own dedicated image.

---

## Source, issues, contributing

- **Source**: [`github.com/tcwlab/betterlint`](https://github.com/tcwlab/betterlint)
- **Issues / feature requests**: [`github.com/tcwlab/betterlint/issues`](https://github.com/tcwlab/betterlint/issues)
- **Docker Hub**: [`hub.docker.com/r/tcwlab/betterlint`](https://hub.docker.com/r/tcwlab/betterlint)

---

## Build, supply chain

Every release is built and published by the repo's own [`.forgejo/workflows/ci.yml`](https://github.com/tcwlab/betterlint/blob/main/.forgejo/workflows/ci.yml) on a Forgejo runner:

- Multi-arch build (`linux/amd64`, `linux/arm64`) via `docker buildx` with `--sbom=true --provenance=mode=max`.
- Trivy vulnerability scan on `HIGH`/`CRITICAL` severity (failures show up as PR comments).
- Self-lint via `betterlint` running against the just-built image.

The `betterlint` SemVer is cut by `semantic-release` from Conventional Commits on `main`.

---

## License

Apache License 2.0. See [`LICENSE`](LICENSE) for the full text.
