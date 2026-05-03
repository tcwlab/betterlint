# ─────────────────────────────────────────────────────────────────────────────
# tcwlab/betterlint
#
# Schlanke Multi-Linter-Alternative zu MegaLinter für TCW-CI-Pipelines.
# Enthält: shellcheck · markdownlint-cli2 · commitlint · spectral · gherkin
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
# STEP 1: base — OS-Pakete (alle Tools werden zur Laufzeit benötigt)
#####
FROM --platform=$BUILDPLATFORM node:22-alpine AS base
ARG BUILDPLATFORM
RUN apk add -U --no-cache \
      python3 \
      py3-pip \
      shellcheck \
      git \
      bash \
      ca-certificates && \
    apk upgrade && \
    rm -rf /var/cache/apk/*

#####
# STEP 2: release — Linter installieren, Wrapper-Skript einbinden, Non-root-User
#####
FROM base AS release
ARG BETTERLINT_VERSION=dev

LABEL org.opencontainers.image.title="betterlint" \
      org.opencontainers.image.description="Compact multi-linter: shellcheck, markdownlint-cli2, commitlint, spectral, gherkin + betterlint wrapper" \
      org.opencontainers.image.vendor="The Chameleon Way" \
      org.opencontainers.image.url="https://hub.docker.com/r/tcwlab/betterlint" \
      org.opencontainers.image.source="https://git.mon.k8b.co/chameleon-ci/betterlint" \
      org.opencontainers.image.version="${BETTERLINT_VERSION}"

# Node-basierte Linter (global, gepinnte Versionen)
RUN npm install --global --no-fund --no-audit \
      markdownlint-cli2@0.17.2 \
      "@commitlint/cli@19" \
      "@commitlint/config-conventional@19" \
      "@stoplight/spectral-cli@6" \
  && npm cache clean --force

# Python-basierte Linter
RUN pip3 install --break-system-packages --no-cache-dir \
      "gherkin-official>=24,<29"

# Wrapper-Skript
COPY betterlint.sh /usr/local/bin/betterlint
RUN chmod +x /usr/local/bin/betterlint

# Non-root user
RUN addgroup -S linter && adduser -S linter -G linter

# Smoke-Test: alle Tools + Wrapper müssen aufrufbar sein
ENV BETTERLINT_VERSION=${BETTERLINT_VERSION}
RUN shellcheck --version \
  && markdownlint-cli2 --version \
  && commitlint --version \
  && spectral --version \
  && python3 -c "from gherkin.parser import Parser; print('gherkin ok')" \
  && betterlint --version

USER linter
WORKDIR /workspace
