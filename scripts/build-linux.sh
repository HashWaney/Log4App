#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ "$(uname -s)" != "Linux" ]; then
  echo "Linux packages must be built on Linux. Current system: $(uname -s)" >&2
  exit 1
fi

for command in flutter dpkg-deb tar; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

VERSION="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' pubspec.yaml | head -n 1)"
if [ -z "$VERSION" ]; then
  echo "Unable to read version from pubspec.yaml." >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64)
    FLUTTER_ARCH="x64"
    DEB_ARCH="amd64"
    ;;
  aarch64|arm64)
    FLUTTER_ARCH="arm64"
    DEB_ARCH="arm64"
    ;;
  *)
    echo "Unsupported Linux architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

flutter pub get
flutter build linux --release

BUNDLE_DIR="$ROOT/build/linux/$FLUTTER_ARCH/release/bundle"
if [ ! -x "$BUNDLE_DIR/log4app" ]; then
  echo "Linux release bundle is missing: $BUNDLE_DIR" >&2
  exit 1
fi

DIST_DIR="$ROOT/dist/linux"
PACKAGE_ROOT="$ROOT/build/linux/package-root"
APP_DIR="$PACKAGE_ROOT/opt/log4app"
mkdir -p "$DIST_DIR"
rm -rf "$PACKAGE_ROOT"
mkdir -p \
  "$APP_DIR" \
  "$PACKAGE_ROOT/DEBIAN" \
  "$PACKAGE_ROOT/usr/bin" \
  "$PACKAGE_ROOT/usr/share/applications" \
  "$PACKAGE_ROOT/usr/share/icons/hicolor/256x256/apps"

cp -a "$BUNDLE_DIR/." "$APP_DIR/"
ln -s /opt/log4app/log4app \
  "$PACKAGE_ROOT/usr/bin/log4app"
install -m 0644 \
  "$ROOT/packaging/linux/android-log-center.png" \
  "$PACKAGE_ROOT/usr/share/icons/hicolor/256x256/apps/log4app.png"
install -m 0644 \
  "$ROOT/packaging/linux/android-log-center.desktop" \
  "$PACKAGE_ROOT/usr/share/applications/log4app.desktop"

cat > "$PACKAGE_ROOT/DEBIAN/control" <<EOF
Package: log4app
Version: $VERSION
Section: utils
Priority: optional
Architecture: $DEB_ARCH
Depends: libgtk-3-0 | libgtk-3-0t64, libblkid1, liblzma5, libstdc++6
Maintainer: Log4App
Description: LAN log collector for apps and devices
 Receives device heartbeats and uploaded app log archives over the local network.
EOF

DEB_PATH="$DIST_DIR/log4app_${VERSION}_${DEB_ARCH}.deb"
TAR_PATH="$DIST_DIR/Log4App-$VERSION-linux-$FLUTTER_ARCH.tar.gz"
rm -f "$DEB_PATH" "$TAR_PATH"
dpkg-deb --build --root-owner-group "$PACKAGE_ROOT" "$DEB_PATH"
tar -C "$BUNDLE_DIR" -czf "$TAR_PATH" .

echo
echo "Linux packages:"
echo "$DEB_PATH"
echo "$TAR_PATH"
