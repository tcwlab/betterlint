# ─────────────────────────────────────────────────────────────────────────────
# tcwlab/betterlint
#
# Schlanke All-in-One-Linter-Alternative zu MegaLinter für TCW-CI-Pipelines.
# Enthält alle Linting-Tools, die wir einsetzen:
#
#   hadolint        Dockerfile-Linting
#   tflint          Terraform/OpenTofu-Linting
#   shellcheck      Shell-Skripte
#   markdownlint    Markdown-Dateien
#   commitlint      Git-Commit-Messages
#   spectral        OpenAPI / AsyncAPI
#   gherkin         Feature-Dateien
#   jq              JSON-Processor (Validierung + Filter)
#   yq              YAML-Processor (Validierung + Filter)
#
# Wrapper: /usr/local/bin/betterlint  (auto-detect, --skip/--only, --markdown)
#
# Unterstützte Plattformen: linux/amd64, linux/arm64
#
# Build (multi-arch):
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     --build-arg BETTERLINT_VERSION=1.0.0 \
#     -t tcwlab/betterlint:1.0.0 --push .
# ─────────────────────────────────────────────────────────────────────────────

#####
# STEP 1: base — OS-Pakete
#####
FROM --platform=$BUILDPLATFORM node:24-alpine AS base
ARG BUILDPLATFORM
# hadolint ignore=DL3018
RUN apk add -U --no-cache \
      python3 \
      py3-pip \
      shellcheck \
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
# STEP 2: release — alle Linter + Wrapper
#####
FROM base AS release
ARG BETTERLINT_VERSION=dev
ARG HADOLINT_VERSION=2.14.0
ARG TFLINT_VERSION=0.62.0

LABEL org.opencontainers.image.title="betterlint" \
      org.opencontainers.image.description="All-in-one linter: hadolint, tflint, shellcheck, markdownlint, commitlint, spectral, gherkin, jq, yq" \
      org.opencontainers.image.vendor="The Chameleon Way" \
      org.opencontainers.image.url="https://hub.docker.com/r/tcwlab/betterlint" \
      org.opencontainers.image.source="https://git.mon.k8b.co/chameleon-ci/betterlint" \
      org.opencontainers.image.version="${BETTERLINT_VERSION}"

# hadolint + tflint: arch-aware Binary-Downloads
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN case "$(apk --print-arch)" in \
      aarch64) \
        HADOLINT_ARCH="arm64" ; \
        TFLINT_ARCH="arm64" ;; \
      x86_64) \
        HADOLINT_ARCH="x86_64" ; \
        TFLINT_ARCH="amd64" ;; \
      *) echo "Nicht unterstützte Architektur: $(apk --print-arch)" && exit 1 ;; \
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

# Node-basierte Linter (global, gepinnte Versionen)
RUN npm install --global --no-fund --no-audit \
      markdownlint-cli2@0.22.1 \
      "@commitlint/cli@20" \
      "@commitlint/config-conventional@20" \
      "@stoplight/spectral-cli@6.15.1" \
  && npm cache clean --force

# Python-basierte Linter
RUN pip3 install --break-system-packages --no-cache-dir \
      "gherkin-official==39.0.0"

# Wrapper-Skript
COPY betterlint.sh /usr/local/bin/betterlint
RUN chmod +x /usr/local/bin/betterlint

# Non-root user
RUN addgroup -S linter && adduser -S linter -G linter

# Smoke-Test: alle Tools + Wrapper müssen aufrufbar sein
ENV BETTERLINT_VERSION=${BETTERLINT_VERSION}
RUN hadolint --version \
  && tflint --version \
  && shellcheck --version \
  && markdownlint-cli2 --version \
  && commitlint --version \
  && spectral --version \
  && python3 -c "from gherkin.parser import Parser; print('gherkin ok')" \
  && jq --version \
  && yq --version \
  && betterlint --version

USER linter
WORKDIR /workspace
