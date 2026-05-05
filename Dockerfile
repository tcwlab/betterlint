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

LABEL org.opencontainers.image.title="betterlint" \
      org.opencontainers.image.description="All-in-one linter: hadolint, tflint, shellcheck, shfmt, markdownlint, commitlint, spectral, gherkin, jq, yq" \
      org.opencontainers.image.vendor="The Chameleon Way" \
      org.opencontainers.image.url="https://hub.docker.com/r/tcwlab/betterlint" \
      org.opencontainers.image.source="https://github.com/tcwlab/betterlint" \
      org.opencontainers.image.version="${BETTERLINT_VERSION}"

# hadolint + tflint: arch-aware binary downloads
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN case "$(apk --print-arch)" in \
      aarch64) \
        HADOLINT_ARCH="arm64" ; \
        TFLINT_ARCH="arm64" ;; \
      x86_64) \
        HADOLINT_ARCH="x86_64" ; \
        TFLINT_ARCH="amd64" ;; \
      *) echo "Unsupported architecture: $(apk --print-arch)" && exit 1 ;; \
    esac && \
    curl -fsSL \
      "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-${HADOLINT_ARCH}" \
      -o /usr/local/bin/hadolint && \
    chmod +x /usr/local/bin/hadolint && \
    curl -fsSL \
      "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${TFLINT_ARCH}.zip" \
      -o /tmp/tflint.zip && \
    unzip -q /tmp/tflint.zip tflint -d /usr/local/bin/ && \
    rm /tmp/tflint.zip && \
    chmod +x /usr/local/bin/tflint && \
    hadolint --version && \
    tflint --version

# Node-based linters (global, version-pinned)
RUN npm install --global --no-fund --no-audit \
      markdownlint-cli2@0.22.1 \
      "@commitlint/cli@20" \
      "@commitlint/config-conventional@20" \
      "@stoplight/spectral-cli@6.15.1" \
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

# Non-root user
RUN addgroup -S linter && adduser -S linter -G linter

# Smoke test: every tool, the wrapper, and all default configs must be present
ENV BETTERLINT_VERSION=${BETTERLINT_VERSION}
RUN hadolint --version \
  && tflint --version \
  && shellcheck --version \
  && shfmt --version \
  && markdownlint-cli2 --version \
  && commitlint --version \
  && spectral --version \
  && python3 -c "from gherkin.parser import Parser; print('gherkin ok')" \
  && jq --version \
  && yq --version \
  && betterlint --version \
  && test -f /etc/betterlint/defaults/markdownlint.json \
  && test -f /etc/betterlint/defaults/commitlint.config.cjs \
  && test -f /etc/betterlint/defaults/spectral.yaml \
  && test -L /etc/betterlint/defaults/node_modules

USER linter
WORKDIR /workspace

# ENTRYPOINT: lock the container surface to the betterlint CLI. Any
# `docker run tcwlab/betterlint:<tag> [args...]` invocation goes straight to
# the wrapper — no implicit shell, no node REPL, no stray binaries reachable
# without an explicit `--entrypoint` override. Naked `docker run` (no args)
# runs the default lint phase against /workspace.
ENTRYPOINT ["/usr/local/bin/betterlint"]
