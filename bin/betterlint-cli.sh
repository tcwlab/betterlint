#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# betterlint-cli — local Docker wrapper for tcwlab/betterlint
#
# Runs the betterlint container against the current working directory and
# forwards every argument to the in-image CLI. The image has ENTRYPOINT
# locked to /usr/local/bin/betterlint, so all "$@" go straight to the
# wrapper — no duplicate "betterlint" needed in the docker run line.
# The --user flag passes the host user's uid/gid so any files patched
# by --fix end up owned by the host user instead of root.
#
# Install (system-wide):
#   sudo install -m 0755 bin/betterlint-cli.sh /usr/local/bin/betterlint
#
# Or, equivalently, drop the shell function from the README into your
# ~/.bashrc / ~/.zshrc — the two paths are functionally identical.
#
# Usage:
#   betterlint                      # plain lint (read-only)
#   betterlint --fix                # auto-fix where possible, then lint
#   betterlint --only hadolint      # any in-image flag is forwarded
#   betterlint --help               # forwarded to the image CLI
#
# Override the image tag with BETTERLINT_IMAGE (default: tcwlab/betterlint:latest):
#   BETTERLINT_IMAGE=tcwlab/betterlint:1.0.0 betterlint --fix
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

IMAGE="${BETTERLINT_IMAGE:-tcwlab/betterlint:latest}"

if ! command -v docker &>/dev/null; then
    echo "betterlint-cli: docker is required but was not found on PATH" >&2
    exit 127
fi

exec docker run --rm \
    -v "$PWD:/workspace" \
    -w /workspace \
    --user "$(id -u):$(id -g)" \
    "$IMAGE" "$@"
