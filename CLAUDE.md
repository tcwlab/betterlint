# betterlint — repo context

> **Onboarding handshake.** Read in this order:
>
> 1. `Projects/CLAUDE.md` (global standards, workspace-local)
> 2. `tcwlab/CLAUDE.md` (toolchain context, consumer API, workspace-local)
> 3. This file (betterlint-specific notes)

---

## What is `betterlint`?

`betterlint` is the all-in-one linter image of the tcwlab toolchain. Instead of the >1 GB MegaLinter footprint (which carries linters TCW does not use), `betterlint` ships a compact Alpine/Node image (~300 MB) with exactly the linters our pipelines rely on: `hadolint` for Dockerfiles, `tflint` for OpenTofu, `shellcheck` for shell scripts, `markdownlint` for docs, `commitlint` for Conventional Commits discipline, `spectral` for OpenAPI/AsyncAPI, and `gherkin-official` for BDD feature files.

The repo is also the **single source of truth for linter versions across the entire TCW world**. If a vertical needs a different `hadolint` version, that is a signal that either the vertical is wrong or the toolchain is overdue for a bump. Drift gets resolved in `betterlint`, never in individual consumer repos.

### Consumers

Every consumer vertical of the TCW world wires `betterlint` into the lint job of its `.forgejo/workflows/ci.yml`:

```yaml
lint:
  runs-on: ubuntu-22.04
  container:
    image: tcwlab/betterlint:1.0.0
  steps:
    - uses: https://data.forgejo.org/actions/checkout@v4
    - run: betterlint --dir .
```

In practice that covers every `Atrium/*`, `Spectrum/*`, `Tally/*`, `IdentServ/*`, `K8Box/*`, `IzyPhlirt/*`, `Testiversum/*`, `Sutagil/*`, plus the other `tcwlab/*` repos (cross-eating-our-own-dogfood: `opentofu`, `buildx`, `trivy`, `semantic-release` are all linted by `betterlint` itself).

---

## What's inside?

The image contents — exactly as declared in the [Dockerfile](https://github.com/tcwlab/betterlint/blob/main/Dockerfile):

| Tool | Version | Source | Job |
|------|---------|--------|-----|
| `hadolint` | `2.14.0` | GitHub release binary, arch-aware | Dockerfile lint |
| `tflint` | `0.62.0` | GitHub release binary, arch-aware | OpenTofu/Terraform lint |
| `shellcheck` | from apk (Alpine 3.23) | Alpine package | Shell script lint |
| `markdownlint-cli2` | `0.22.1` | npm global | Markdown lint |
| `@commitlint/cli` | `20.x` | npm global | Conventional Commits validator |
| `@commitlint/config-conventional` | `20.x` | npm global | Default rule set |
| `@stoplight/spectral-cli` | `6.15.1` | npm global | OpenAPI/AsyncAPI lint |
| `gherkin-official` | `39.0.0` | pip3 (`--break-system-packages`) | Gherkin syntax validator |

Plus the central wrapper [`betterlint.sh`](https://github.com/tcwlab/betterlint/blob/main/betterlint.sh) installed as `/usr/local/bin/betterlint`. Auto-detect logic: it inspects the workdir and runs only the linters whose file patterns match. Options: `--skip TOOL,...`, `--only TOOL,...`, `--dir PATH`, `--markdown` (for PR comment output), `--version`.

Base image: `node:24-alpine` as a BUILDPLATFORM-aware multi-stage build. The image is built for `linux/amd64` and `linux/arm64`.

User: non-root `linter` user. Workdir: `/workspace` (the convention for Forgejo container jobs).

---

## Tool versions and pinning strategy

Every tool version is hard-baked into the Dockerfile as `ARG <TOOL>_VERSION=<x.y.z>`. Build args set in the CI workflow override the default and ensure that the tag pushed and the image contents agree.

### Updates

For now manual, because tcwlab is too small for Renovate. Workflow:

1. In the PR, bump the `ARG <TOOL>_VERSION` default.
2. Smoke-test in the build job (the Dockerfile's last stage runs a smoke-test block).
3. Conventional Commits message: `feat: bump <tool> to <version>`.
4. semantic-release cuts a new `betterlint` SemVer and pushes `tcwlab/betterlint:<x.y.z>`.
5. Update `tcwlab/versions.yaml` at the top level of the workspace.

For small tool updates (e.g. a `tflint` patch): patch-bump the `betterlint` SemVer. For tool major updates or a new tool: minor bump.

### Discipline

Never use `latest` as a source pin. Every linter binary must land in a concrete tag reproducibly — otherwise "CI was green" is worthless.

---

## Release procedure

[`semantic-release`](https://github.com/tcwlab/betterlint/blob/main/.releaserc) is configured with:

- `@semantic-release/commit-analyzer` → derive the SemVer step from Conventional Commits
- `@semantic-release/release-notes-generator` → changelog
- `@saithodev/semantic-release-gitea` → Forgejo release + tag
- `@semantic-release/git` → commit tag/changelog

Tag scheme: `v<x.y.z>`, Docker Hub tag: `tcwlab/betterlint:<x.y.z>` plus rolling `latest`. The two tags are pushed in parallel by the publish job (multi-arch via Buildx).

Branch protection is on for `main` (status check `ci`, squash-merge, branch-delete-after-merge). All changes go through PRs from `claude/<slug>` branches.

---

## What to do on a version bump

1. **PR on `claude/bump-<tool>-<version>`**: change `ARG <TOOL>_VERSION`.
2. **Run the smoke tests** — the smoke-test block in the Dockerfile checks `<tool> --version`. If that passes locally / in CI, the binary is compatible.
3. **Check consumer paths**: in the templates ([`templates/iac-ci.yml`](https://github.com/tcwlab/templates/blob/main/iac-ci.yml), [`templates/service-ci.yml`](https://github.com/tcwlab/templates/blob/main/service-ci.yml), [`templates/docker-image-ci.yml`](https://github.com/tcwlab/templates/blob/main/docker-image-ci.yml)) `BETTERLINT_VERSION:` is set as a default. On a major bump in `betterlint`, raise the templates separately so newly bootstrapped consumer repos pick up the new default.
4. **Changelog**: produced by semantic-release automatically — but verify that the commit message makes the change clear to consumers.
5. **Consumer outreach** (on breaking changes): add a short note in `tcwlab/CLAUDE.md` if consumers need to bump `BETTERLINT_VERSION`.

---

## What does NOT belong in this image

- **Language compilers / build tools** (Java, Go, Rust, Kotlin). `betterlint` is a linter image, not a build image. Build tools belong in repo-specific build images or dedicated tcwlab build images (e.g. `buildx`).
- **Full test runners** (junit, gotest, vitest). Tests run in the service container, not in the linter.
- **Heavy-weight scanners** (sonarqube-scanner, snyk-cli, prisma-cli). We stay deliberately lightweight.
- **Language-specific style linters** (eslint, prettier, ktlint, gofmt, rustfmt). These run in the language's own container; `betterlint` only does cross-cutting linting.
- **Application security scanners** (Trivy, Grype, Snyk). Trivy has its own `tcwlab/trivy` image — security scanning and linting are clearly separate CI phases.

When somebody asks "can't we add X here too?", the default answer is **"No, build a dedicated image."** Only when three or more verticals need X in the lint job do we consider a bump.

---

## Consumer snippets

### Standard lint job

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

### Selective (only specific linters)

```yaml
- run: betterlint --only hadolint,shellcheck
- run: betterlint --skip commitlint,spectral
```

### Markdown output for PR comments

```yaml
- name: Lint with Markdown report
  run: |
    set +e
    betterlint --dir . --markdown 2>&1 | tee /tmp/betterlint-report.md
    LINT_EXIT="${PIPESTATUS[0]}"
    exit "${LINT_EXIT}"
```

A follow-up step can post the report content as a PR comment via the Forgejo API (the pattern exists in the `tcwlab` image repos themselves).

---

## Known pain points / open topics

- **shellcheck via apk**: the version is tied to Alpine 3.23 and not pinnable independently. If a consumer needs a specific shellcheck version, the image update has to ride on an Alpine major bump.
- **gherkin-official via `--break-system-packages`**: an Alpine PEP-668 workaround. As long as we stay on Alpine and do not want venvs in a linter image, this stays. Acceptably ugly.
- **markdownlint-cli2 0.22.1** is the version converged on across TCW. Higher versions caused cross-repo drift in the `.markdownlint.json` schema — bump only after coordinated consumer migration.
- **`commitlint`** major updates often require adjustments in consumer `.commitlintrc.json` files. On a major bump, walk the consumer table in `tcwlab/CLAUDE.md` first.
- **Bootstrap problem**: betterlint cannot lint itself (chicken-and-egg). The repo's own `ci.yml` runs the lint job against a fixed `1.0.0` image, not against the current build output.
