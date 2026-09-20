#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[1/4] Checking Flutter..."
flutter --version

echo "[2/4] Creating desktop runners if missing..."
flutter create --platforms=macos .

echo "[3/4] Enabling macOS incoming network connections..."
python3 - <<'PY'
from pathlib import Path

for relative in [
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
]:
    path = Path(relative)
    if not path.exists():
        continue
    text = path.read_text()
    key = '<key>com.apple.security.network.server</key>'
    if key not in text:
        text = text.replace(
            '</dict>',
            '\t<key>com.apple.security.network.server</key>\n\t<true/>\n</dict>',
            1,
        )
        path.write_text(text)
        print(f'patched {relative}')
    else:
        print(f'already configured {relative}')
PY

echo "[4/4] Resolving packages..."
flutter pub get

echo
echo "Bootstrap complete."
echo "Run on macOS: flutter run -d macos"
