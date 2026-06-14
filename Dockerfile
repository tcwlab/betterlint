# ─────────────────────────────────────────────────────────────────────────────
# tcwlab/betterlint
#
# Compact all-in-one linter alternative to MegaLinter for TCW CI pipelines.
# Bundles every linting tool we use:
#
#   hadolint        Dockerfile linting
#   tflint          Terraform/OpenTofu linting
#   shellcheck      Shell scripts
#   shfmt           Shell script auto-formatter (used by --fix)
#   markdownlint    Markdown files
#   commitlint      Git commit messages
#   spectral        OpenAPI / AsyncAPI
#   gherkin         Feature files
#   prettier        Code/asset formatter — JS/TS/JSON/CSS/HTML (used by --fix)
#   eslint          JS/TS linter + auto-fixer (used by --fix; ships flat-config default)
#   yamlfmt         YAML auto-formatter (used by --fix)
#   jq              JSON processor (validation + filter)
#   yq              YAML processor (validation + filter)
#
# Wrapper: /usr/local/bin/betterlint  (auto-detect, --skip/--only, --fix, --markdown)
#
# Supported platforms: linux/amd64, linux/arm64
#
# Build (multi-arch):
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     --build-arg BETTERLINT_VERSION=1.0.0 \
#     -t tcwlab/betterlint:1.0.0 --push .
# ─────────────────────────────────────────────────────────────────────────────

#####
# STEP 1: base — OS packages
#####
FROM --platform=$BUILDPLATFORM node:24-alpine AS base
ARG BUILDPLATFORM
# hadolint ignore=DL3018
RUN apk add -U --no-cache \
      python3 \
      py3-pip \
      shellcheck \
      shfmt \
      curl \
      unzip \
      git \
      bash \
      ca-certificates \
      jq \
      yq && \
    apk upgrade && \
    rm -rf /var/cache/apk/*

#####
# STEP 2: release — every linter + the wrapper
#####
FROM base AS release
ARG BETTERLINT_VERSION=dev
ARG HADOLINT_VERSION=2.14.0
ARG TFLINT_VERSION=0.62.0
ARG YAMLFMT_VERSION=0.21.0

# Pinned SHA256 sums for every binary download. Build fails if a download
# does not match the recorded checksum — defends against upstream tampering
# and accidental release re-cuts. Update these together with the *_VERSION
# bumps. Compute via:
#   curl -fsSL <url> | sha256sum
ARG HADOLINT_SHA256_AMD64=6bf226944684f56c84dd014e8b979d27425c0148f61b3bd99bcc6f39e9dc5a47
ARG HADOLINT_SHA256_ARM64=331f1d3511b84a4f1e3d18d52fec284723e4019552f4f47b19322a53ce9a40ed
ARG TFLINT_SHA256_AMD64=000400d7f4c2236d9ed4b35fec3ee95617c3747571593cc6138169fc78cc226a
ARG TFLINT_SHA256_ARM64=064206ec85adaf90f637c880eb3cd5a8e07ddce09e4da7c813eb362cb794f95f
ARG YAMLFMT_SHA256_AMD64=1f300d9257b232bb3b541d7fb1b0e6b3c121bcbab381c86cd38cb8722be8a566
ARG YAMLFMT_SHA256_ARM64=5b2689c963b177271330c5ce8ca7396751107e5a826be46f03d2cb9b6f0c7784

LABEL org.opencontainers.image.title="betterlint" \
      org.opencontainers.image.description="All-in-one linter + auto-fixer: hadolint, tflint, shellcheck, shfmt, markdownlint, commitlint, spectral, gherkin, prettier, eslint, yamlfmt, jq, yq" \
      org.opencontainers.image.vendor="The Chameleon Way" \
      org.opencontainers.image.url="https://hub.docker.com/r/tcwlab/betterlint" \
      org.opencontainers.image.source="https://github.com/tcwlab/betterlint" \
      org.opencontainers.image.documentation="https://github.com/tcwlab/betterlint/blob/main/README.md" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${BETTERLINT_VERSION}"

# hadolint + tflint + yamlfmt: arch-aware binary downloads with SHA256
# verification. The checksum check (sha256sum -c) aborts the build with a
# non-zero exit code on any mismatch, so a tampered or unexpectedly-replaced
# upstream release artifact never lands in the final image.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN case "$(apk --print-arch)" in \
      aarch64) \
        HADOLINT_ARCH="arm64" ; \
        TFLINT_ARCH="arm64" ; \
        YAMLFMT_ARCH="arm64" ; \
        HADOLINT_SHA256="${HADOLINT_SHA256_ARM64}" ; \
        TFLINT_SHA256="${TFLINT_SHA256_ARM64}" ; \
        YAMLFMT_SHA256="${YAMLFMT_SHA256_ARM64}" ;; \
      x86_64) \
        HADOLINT_ARCH="x86_64" ; \
        TFLINT_ARCH="amd64" ; \
        YAMLFMT_ARCH="x86_64" ; \
        HADOLINT_SHA256="${HADOLINT_SHA256_AMD64}" ; \
        TFLINT_SHA256="${TFLINT_SHA256_AMD64}" ; \
        YAMLFMT_SHA256="${YAMLFMT_SHA256_AMD64}" ;; \
      *) echo "Unsupported architecture: $(apk --print-arch)" && exit 1 ;; \
    esac && \
    curl -fsSL \
      "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-${HADOLINT_ARCH}" \
      -o /usr/local/bin/hadolint && \
    echo "${HADOLINT_SHA256}  /usr/local/bin/hadolint" | sha256sum -c - && \
    chmod +x /usr/local/bin/hadolint && \
    curl -fsSL \
      "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${TFLINT_ARCH}.zip" \
      -o /tmp/tflint.zip && \
    echo "${TFLINT_SHA256}  /tmp/tflint.zip" | sha256sum -c - && \
    unzip -q /tmp/tflint.zip tflint -d /usr/local/bin/ && \
    rm /tmp/tflint.zip && \
    chmod +x /usr/local/bin/tflint && \
    curl -fsSL \
      "https://github.com/google/yamlfmt/releases/download/v${YAMLFMT_VERSION}/yamlfmt_${YAMLFMT_VERSION}_Linux_${YAMLFMT_ARCH}.tar.gz" \
      -o /tmp/yamlfmt.tar.gz && \
    echo "${YAMLFMT_SHA256}  /tmp/yamlfmt.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/yamlfmt.tar.gz -C /usr/local/bin/ yamlfmt && \
    rm /tmp/yamlfmt.tar.gz && \
    chmod +x /usr/local/bin/yamlfmt && \
    hadolint --version && \
    tflint --version && \
    yamlfmt --version

# Node-based linters and formatters (global, version-pinned where stable).
# prettier/eslint use caret ranges so consumer-config plugins resolve against
# a single shared major; the SemVer floor protects against accidental regress.
RUN npm install --global --no-fund --no-audit \
      markdownlint-cli2@0.22.1 \
      "@commitlint/cli@20" \
      "@commitlint/config-conventional@20" \
      "@stoplight/spectral-cli@6.15.1" \
      "prettier@^3" \
      "eslint@^9" \
      "@eslint/js@^9" \
      "globals@^15" \
  && npm cache clean --force

# Python-based linters
RUN pip3 install --break-system-packages --no-cache-dir \
      "gherkin-official==39.0.0"

# Default configs: applied when the consumer repo ships no own config.
# The wrapper detects a missing config and passes --config explicitly to
# the corresponding fallback path. The symlink makes the npm-global
# packages (e.g. @commitlint/config-conventional) resolvable from
# /etc/betterlint/defaults/ via standard Node require().
COPY defaults/ /etc/betterlint/defaults/
RUN ln -s /usr/local/lib/node_modules /etc/betterlint/defaults/node_modules

# Wrapper script
COPY betterlint.sh /usr/local/bin/betterlint
RUN chmod +x /usr/local/bin/betterlint

# Non-root user with a fixed UID/GID so consumer host-bind-mounts produce
# predictable file ownership across every machine that runs the image.
# UID/GID 10001 is well above the Linux SYS_UID_MAX default (60000 cap, but
# distro-typical service accounts stop around 999) and below the OpenShift
# arbitrary-uid range — no collisions with host system accounts.
RUN addgroup -S -g 10001 betterlint \
 && adduser  -S -D -h /home/betterlint -u 10001 -G betterlint betterlint \
 && mkdir -p /home/betterlint \
 && chown 10001:10001 /home/betterlint

# Smoke test: every tool, the wrapper, and all default configs must be present
ENV BETTERLINT_VERSION=${BETTERLINT_VERSION}
RUN hadolint --version \
  && tflint --version \
  && shellcheck --version \
  && shfmt --version \
  && markdownlint-cli2 --version \
  && commitlint --version \
  && spectral --version \
  && prettier --version \
  && eslint --version \
  && yamlfmt --version \
  && python3 -c "from gherkin.parser import Parser; print('gherkin ok')" \
  && jq --version \
  && yq --version \
  && betterlint --version \
  && test -f /etc/betterlint/defaults/markdownlint.json \
  && test -f /etc/betterlint/defaults/commitlint.config.cjs \
  && test -f /etc/betterlint/defaults/spectral.yaml \
  && test -f /etc/betterlint/defaults/eslint.config.js \
  && test -L /etc/betterlint/defaults/node_modules

# Drop privileges. Numeric form so Kubernetes / OpenShift admission
# controllers that enforce runAsNonRoot can confirm the UID without
# resolving /etc/passwd inside the container.
USER 10001:10001
WORKDIR /workspace

# Disable the inherited base-image healthcheck (if any). A linter image
# is invoked one-shot; a long-running healthcheck process makes no sense
# and would only widen the runtime surface.
HEALTHCHECK NONE

# ENTRYPOINT: lock the container surface to the betterlint CLI. Any
# `docker run tcwlab/betterlint:<tag> [args...]` invocation goes straight to
# the wrapper — no implicit shell, no node REPL, no stray binaries reachable
# without an explicit `--entrypoint` override. Naked `docker run` (no args)
# runs the default lint phase against /workspace.
ENTRYPOINT ["/usr/local/bin/betterlint"]
