#!/usr/bin/env bash
set -euo pipefail

info() { printf '\033[1;34m[build]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

[[ -f openrpt.pro ]] || die "Run this script from the OpenRPT repository root."

# prefer the distro libdmtx unless caller overrides
export USE_SYSTEM_DMTX="${USE_SYSTEM_DMTX:-1}"

if command -v apt-get >/dev/null 2>&1; then
  if [[ "${SKIP_DEP_INSTALL:-}" != "1" ]]; then
    if sudo -n true 2>/dev/null; then
      info "Installing Qt5 build prerequisites (requires sudo)…"
      sudo apt-get update
      sudo apt-get install -y build-essential devscripts debhelper dpkg-dev fakeroot \
        qtbase5-dev qttools5-dev qttools5-dev-tools libqt5sql5-psql libqt5svg5-dev \
        libqt5xmlpatterns5-dev libdmtx-dev libpq-dev libglu1-mesa-dev
    else
      warn "Skipping automatic dependency installation (sudo not available)."
      warn "Install manually or rerun with SKIP_DEP_INSTALL=1."
    fi
  else
    info "Skipping dependency installation (SKIP_DEP_INSTALL=1)."
  fi
else
  warn "apt-get not found; ensure Qt5 development packages and debhelper are installed."
fi

BUILD_DIR="${BUILD_DIR:-build-full}"
info "Configuring shadow build in $BUILD_DIR …"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
pushd "$BUILD_DIR" >/dev/null

qmake ../openrpt.pro
info "Compiling (this may take a while)…"
make -j"${JOBS:-$(nproc)}"

popd >/dev/null

STAGE="${STAGE_DIR:-package-root}"
rm -rf "$STAGE"
ARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
VERSION="${VERSION:-$(git describe --tags --dirty 2>/dev/null || echo 3.3.13)}"
PKGNAME="openrpt-full"
PKGDIR="$STAGE/${PKGNAME}_${VERSION%%-*}_amd64"
info "Staging files under $PKGDIR …"

install -d "$PKGDIR/DEBIAN"
install -d "$PKGDIR/usr/bin"
install -d "$PKGDIR/usr/lib/$ARCH"
install -d "$PKGDIR/usr/share/openrpt"
install -d "$PKGDIR/usr/share/applications"
install -d "$PKGDIR/usr/share/doc/$PKGNAME"

# Binaries
if compgen -G "$BUILD_DIR/bin/*" >/dev/null; then
  cp -a "$BUILD_DIR"/bin/* "$PKGDIR/usr/bin/"
else
  warn "No binaries found under $BUILD_DIR/bin"
fi

# Shared libraries
if compgen -G "$BUILD_DIR/lib/lib*" >/dev/null; then
  cp -a "$BUILD_DIR"/lib/lib*.so* "$PKGDIR/usr/lib/$ARCH/" 2>/dev/null || true
fi

# Resources (images, translations)
if [[ -d OpenRPT/images ]]; then
  cp -a OpenRPT/images "$PKGDIR/usr/share/openrpt/"
fi
install -d "$PKGDIR/usr/share/openrpt/translations"
find "$REPO_ROOT" \( -path "$REPO_ROOT/build-*" -o -path "$REPO_ROOT/.git" \) -prune -o -name '*.qm' -print 2>/dev/null \
  | while read -r qm; do
      cp -a "$qm" "$PKGDIR/usr/share/openrpt/translations/" 2>/dev/null || true
    done
find "$BUILD_DIR" -name '*.qm' -exec cp -a {} "$PKGDIR/usr/share/openrpt/translations/" \; 2>/dev/null || true

# Desktop entries
for desktop in openrpt.desktop importrptgui.desktop importmqlgui.desktop; do
  if [[ -f $desktop ]]; then
    install -m 0644 "$desktop" "$PKGDIR/usr/share/applications/$desktop"
  fi
done

# Documentation
for doc in README README.md README.txt COPYING; do
  if [[ -f $doc ]]; then
    install -m 0644 "$doc" "$PKGDIR/usr/share/doc/$PKGNAME/$doc"
  fi
done

# Strip binaries if possible
if command -v strip >/dev/null 2>&1; then
  find "$PKGDIR/usr/bin" -type f -exec strip --strip-unneeded {} + 2>/dev/null || true
  find "$PKGDIR/usr/lib/$ARCH" -type f -name 'lib*.so*' -exec strip --strip-unneeded {} + 2>/dev/null || true
fi

cat > "$PKGDIR/DEBIAN/control" <<CONTROL
Package: $PKGNAME
Version: ${VERSION%%-*}
Section: misc
Priority: optional
Architecture: amd64
Maintainer: OpenRPT Maintainers <maintainers@example.com>
Depends: libqt5core5t64 (>= 5.15), libqt5gui5t64 (>= 5.15), libqt5widgets5t64 (>= 5.15), libqt5sql5t64 (>= 5.15), libqt5sql5-psql, libqt5printsupport5t64, libqt5svg5, libdmtx0a, libpq5
Description: OpenRPT report writer (full GUI suite)
 This package ships the classic OpenRPT applications including the
 report writer, renderer, MetaSQL tools, and database utilities.
CONTROL
chmod 0644 "$PKGDIR/DEBIAN/control"

info "Building Debian package …"
dpkg-deb --build "$PKGDIR"

OUTPUT_DEB="$PKGDIR.deb"
info "Package generated: $OUTPUT_DEB"

ls -lh "$OUTPUT_DEB"
