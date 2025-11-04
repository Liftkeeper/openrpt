#!/usr/bin/env bash
set -euo pipefail

info() { printf '\033[1;34m[build]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

[[ -f openrpt.pro ]] || die "This script must be run from the OpenRPT repository root."

if command -v apt-get >/dev/null 2>&1; then
  if [[ "${SKIP_DEP_INSTALL:-}" != "1" ]]; then
    if sudo -n true 2>/dev/null; then
      info "Installing build prerequisites (requires sudo)…"
      sudo apt-get update
      sudo apt-get install -y build-essential devscripts debhelper qt6-base-dev qt6-base-dev-tools
    else
      info "Skipping automatic dependency installation (sudo not available)."
      info "Install manually or rerun with SKIP_DEP_INSTALL=1."
    fi
  else
    info "Skipping dependency installation (SKIP_DEP_INSTALL=1)."
  fi
else
  info "apt-get not found; make sure build-essential, devscripts, debhelper-compat, and Qt6 dev packages are installed."
fi

info "Cleaning previous build outputs…"
fakeroot debian/rules clean >/dev/null || die "Failed to clean previous builds"
rm -rf debian/artifacts

info "Building openrpt-cli Debian package…"
fakeroot debian/rules binary || die "Package build failed"

if [[ ! -d debian/artifacts ]]; then
  die "Expected debian/artifacts to exist after build."
fi

info "Build complete. Generated packages:"
ls -1 debian/artifacts
