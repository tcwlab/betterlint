# tcwlab/betterlint

> Compact multi-linter image for CI pipelines. Bundles every linter that TCW projects actually need (`hadolint`, `tflint`, `shellcheck`, `shfmt`, `markdownlint`, `commitlint`, `spectral`, `gherkin`, plus `jq` and `yq`) into a single Alpine-based image with a smart auto-detect wrapper. Drop-in alternative to MegaLinter when you want a smaller, faster image with sensible defaults.

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
| [`shfmt`](https://github.com/mvdan/sh) | from Alpine 3.23 apk | Shell script auto-formatter (used by `--fix`) |
| [`markdownlint-cli2`](https://github.com/DavidAnson/markdownlint-cli2) | `0.22.1` | Markdown linting (auto-fix supported) |
| [`@commitlint/cli`](https://commitlint.js.org/) | `20.x` | Conventional Commits validation |
| [`@commitlint/config-conventional`](https://commitlint.js.org/reference/configuration.html) | `20.x` | Default commitlint rule set |
| [`@stoplight/spectral-cli`](https://stoplight.io/open-source/spectral) | `6.15.1` | OpenAPI / AsyncAPI linting |
| [`gherkin-official`](https://pypi.org/project/gherkin-official/) | `39.0.0` | Gherkin/BDD `.feature` syntax validation |
| `jq` | from Alpine apk | JSON processor (validation + filter) |
| `yq` | from Alpine apk | YAML processor (validation + filter) |
| `betterlint` (wrapper) | `1.0.0` | Auto-detect runner (`/usr/local/bin/betterlint`) |

Base image: `node:24-alpine`. Default workdir: `/workspace`. Default user: `betterlint` (non-root, fixed UID/GID `10001:10001`). See [Security posture](#security-posture) for the rationale and the recommended hardened `docker run` line.

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
  --only hadolint,shellcheck
```

### Skip specific tools

```bash
docker run --rm -v "$PWD:/workspace" tcwlab/betterlint:1.0.0 \
  --skip commitlint,spectral
```

### Generate a Markdown report (for PR comments)

```bash
docker run --rm -v "$PWD:/workspace" tcwlab/betterlint:1.0.0 \
  --markdown > lint-report.md
```

> The image's `ENTRYPOINT` is locked to `/usr/local/bin/betterlint`, so every
> `docker run` invocation passes its arguments straight to the CLI. No need to
> retype `betterlint` between the image tag and the flag. (Old callers that
> still write `… tcwlab/betterlint:1.0.0 betterlint --only foo` keep working
> — the wrapper silently absorbs a leading `betterlint` arg for back-compat.)

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
| `--fix`           | Run auto-correctable fixers in-place, then lint as usual ([details](#auto-fix-mode)) |
| `--markdown`      | Emit a Markdown table (suitable for PR comments) |
| `--version`       | Print the wrapper version and exit |
| `--help`          | Print the full help text |

Equivalent environment variables (overridden by CLI flags):

| Variable | Equivalent flag |
|----------|-----------------|
| `BETTERLINT_SKIP` | `--skip` |
| `BETTERLINT_ONLY` | `--only` |
| `BETTERLINT_DIR`  | `--dir` |
| `BETTERLINT_FIX`  | `--fix` (set to `1`) |

### Selective linter invocation

The five canonical patterns:

| Action | Example |
|--------|---------|
| Run a single linter | `betterlint --only markdownlint` |
| Run a list of linters | `betterlint --only markdownlint,shellcheck` |
| Skip a single linter | `betterlint --skip hadolint` |
| Skip a list of linters | `betterlint --skip hadolint,tflint` |
| Combine selection + auto-fix | `betterlint --fix --only markdownlint,shellcheck` |

`--only` and `--skip` are **mutually exclusive** — the wrapper exits with
code `2` and a clear error message if both are passed. Unknown linter names
also fail fast with exit `2` instead of silently doing nothing.

Known linter names (use these exactly with `--only` / `--skip`):
`hadolint`, `tflint`, `shellcheck`, `markdownlint`, `commitlint`, `spectral`,
`gherkin`.

The same patterns work via the host wrapper or as direct `docker run`
arguments (the image's `ENTRYPOINT` forwards everything to the CLI):

```bash
betterlint --only markdownlint                    # via shell function / wrapper
docker run --rm -v "$PWD:/workspace" \
  tcwlab/betterlint:1.0.0 --only markdownlint     # direct docker run
```

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

> **Path-agnostic scanning.** The wrapper scans the container's current
> working directory, not a hardcoded `/workspace`. The image's `WORKDIR`
> is `/workspace` so naked `docker run` lands there, but any custom mount
>
> - `-w` works transparently — `-v "$PWD:/work" -w /work`, `-v "$PWD:/repo" -w /repo`,
> etc. Use `--dir PATH` (or `BETTERLINT_DIR`) to override explicitly.

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

## Auto-fix mode

```bash
# Pure lint (default — read-only)
docker run --rm -v "$PWD:/workspace" tcwlab/betterlint:latest

# Auto-fix where possible, then lint to report what's left
docker run --rm -v "$PWD:/workspace" tcwlab/betterlint:latest --fix
```

`--fix` runs in two phases:

1. **Fix phase** — every fix-capable tool patches matching files in-place.
2. **Lint phase** — the regular linters run, including the ones that have no
   auto-fix mode. Anything not fixable surfaces here for manual cleanup.

The exit code is `max()` over both phases — so "all fixed but `hadolint` still
flagged something" still fails the run. Combinable with `--skip` / `--only` /
`--dir` (e.g. `betterlint --fix --only markdownlint` to fix only Markdown).

### Auto-fix support matrix

| Tool | Mode under `--fix` | Notes |
|------|--------------------|-------|
| `markdownlint-cli2` | 🛠️ in-place fix (`--fix`) | Bundled in image |
| `shfmt` | 🛠️ in-place format (`-w`) | Bundled in image; runs against `*.sh` |
| `prettier` | 🛠️ in-place fix (`--write`) | **Not bundled** — runs only when `prettier` is on PATH |
| `eslint` | 🛠️ in-place fix (`--fix`) | **Not bundled** — runs only when `eslint` is on PATH |
| `yamlfmt` | 🛠️ in-place format | **Not bundled** — runs only when `yamlfmt` is on PATH |
| `hadolint` | 📋 report-only | No auto-fix mode upstream |
| `tflint` | 📋 report-only | No auto-fix mode upstream |
| `shellcheck` | 📋 report-only | Use `shfmt` for formatting; `shellcheck` reports semantic issues |
| `commitlint` | 📋 report-only | Commit messages can't be auto-fixed |
| `spectral` | 📋 report-only | No auto-fix mode upstream |
| `gherkin` | 📋 report-only | Syntax validator, no auto-fix |

Tools marked **Not bundled** are detected at runtime — when missing they
appear in the report with a `⚠️` marker so users know why no fix was attempted.
Mount your own toolchain into the container (or run `--fix` outside the
container against the same workdir) to enable them.

> **File ownership when using `--fix`:** files patched inside the container are
> owned by whoever the container ran as. The README's [`Install as
> betterlint CLI`](#install-as-betterlint-cli) snippets pass
> `--user "$(id -u):$(id -g)"` so fixes land with the right owner on the host.

---

## Install as `betterlint` CLI

Two ways to call `betterlint` from anywhere on your host without typing the
full `docker run …` line every time. They are functionally identical —
`betterlint` plain → lint, `betterlint --fix` → auto-fix mode,
`betterlint --help` → forwarded to the in-image CLI, `betterlint <file>` →
file/flag arguments forwarded.

### Option 1 (recommended): shell function in `~/.bashrc` / `~/.zshrc`

Minimal-invasive — no PATH mucking, no extra files on disk.

```bash
betterlint() {
    docker run --rm \
        -v "$PWD:/workspace" \
        -w /workspace \
        --user "$(id -u):$(id -g)" \
        tcwlab/betterlint:latest "$@"
}
```

Append the snippet to your shell rc file and `source` it (or open a new
shell). Pin to a specific tag in production by replacing `:latest`.

### Option 2: standalone wrapper script (system-wide)

For cases where a shell function isn't an option (cron jobs, Makefiles,
non-interactive shells, multi-user systems). Drop
[`bin/betterlint-cli.sh`](./bin/betterlint-cli.sh) into `/usr/local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/tcwlab/betterlint/main/bin/betterlint-cli.sh \
  -o /tmp/betterlint && \
  chmod +x /tmp/betterlint && \
  sudo mv /tmp/betterlint /usr/local/bin/betterlint
```

Or, if you've cloned the repo:

```bash
sudo install -m 0755 bin/betterlint-cli.sh /usr/local/bin/betterlint
```

Override the image tag at runtime with `BETTERLINT_IMAGE`:

```bash
BETTERLINT_IMAGE=tcwlab/betterlint:1.0.0 betterlint --fix
```

---

## Security posture

The image is built to run under tight runtime restrictions so consumer pipelines can drop it into hardened environments without extra wrapping.

### Hardening assumptions baked into the image

- **`ENTRYPOINT` lockdown.** The image's `ENTRYPOINT` is fixed to `/usr/local/bin/betterlint`. `docker run <image> /bin/sh` does **not** open a shell; the shell argument is forwarded to the wrapper as a CLI arg. Reaching a shell requires an explicit `--entrypoint` override, which the CI gate verifies on every build.
- **Non-root by default — fixed UID/GID `10001:10001`.** The `betterlint` user is created with a deterministic UID so host bind-mounts produce predictable file ownership across machines, and so Kubernetes / OpenShift admission controllers that enforce `runAsNonRoot` can confirm the UID without resolving `/etc/passwd` inside the container.
- **SHA256-verified binary downloads.** `hadolint` and `tflint` are installed via `curl` from upstream GitHub releases and then verified against pinned SHA256 sums in the Dockerfile (`HADOLINT_SHA256_*`, `TFLINT_SHA256_*` build args). A mismatch fails the build — no tampered or accidentally re-cut release artifact ever reaches the final image.
- **No healthcheck.** `HEALTHCHECK NONE` is set explicitly so no inherited or default healthcheck process keeps running in the background. The image is invoked one-shot.
- **`--read-only`, `--cap-drop=ALL`, and `--security-opt=no-new-privileges` compatible.** The CI pipeline runs a hardened smoke-test on every build that exercises the image under all three flags simultaneously. If any flag would break the wrapper, the build fails before publish.

### Recommended `docker run`

```bash
docker run --rm \
  --read-only \
  --tmpfs /tmp \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --user "$(id -u):$(id -g)" \
  -v "$PWD:/workspace" \
  tcwlab/betterlint:latest
```

`--user "$(id -u):$(id -g)"` overrides the image's default UID so files written by `--fix` land with the host user's ownership. The image accepts any UID — the default `10001:10001` only kicks in when `--user` is not passed.

### Hardened wrapper variant

Drop-in replacement for the shell function in [Install as `betterlint` CLI](#install-as-betterlint-cli) that always passes the security flags above:

```bash
betterlint() {
    docker run --rm \
        --read-only --tmpfs /tmp \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        --user "$(id -u):$(id -g)" \
        -v "$PWD:/workspace" \
        -w /workspace \
        tcwlab/betterlint:latest "$@"
}
```

### SBOM and provenance

Each published tag carries an SPDX SBOM and `mode=max` provenance attestation produced by `docker buildx`. Inspect via:

```bash
docker buildx imagetools inspect tcwlab/betterlint:<tag> \
  --format '{{ json .SBOM }}'

docker buildx imagetools inspect tcwlab/betterlint:<tag> \
  --format '{{ json .Provenance }}'
```

### Trivy gate in CI

Every build runs a two-pass Trivy scan against the image:

1. **Hard gate** during `build-test`: `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`. Any HIGH or CRITICAL vulnerability with an upstream fix available fails the build immediately. Downstream `security` and `publish` jobs do not run on a gated failure.
2. **Reporting pass** during `security`: full scan including unfixable CVEs, posted as a PR comment so maintainers retain visibility. The most recent scan results are always available on the [Docker Hub vulnerability tab](https://hub.docker.com/r/tcwlab/betterlint/tags).

### Scope and non-goals

This posture covers what `betterlint` ships in its image. Things explicitly out of scope:

- **The lint tools themselves are upstream code.** We pin versions, hash-verify binary downloads, and scan the image layers with Trivy, but we do not audit the source of `hadolint`, `tflint`, `markdownlint-cli2`, or any other bundled tool.
- **Consumer Dockerfiles and configs are the consumer's responsibility.** A repo that mounts secrets into `/workspace` will see those secrets inside the container — the image cannot defend against that.
- **`betterlint` is not a security scanner.** Application-level scanning is `tcwlab/trivy`'s job. Lint and scan are separate pipeline phases on purpose.

To report a security issue, open an [issue](https://github.com/tcwlab/betterlint/issues) marked `security` or contact the maintainers privately.

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
