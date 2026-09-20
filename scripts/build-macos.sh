#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -d macos ]; then
  echo "macos runner missing. Run ./scripts/bootstrap.sh first."
  exit 1
fi

python3 - <<'PY'
from pathlib import Path
for relative in [
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
]:
    path = Path(relative)
    if not path.exists():
        raise SystemExit(f'missing {relative}')
    text = path.read_text()
    if '<key>com.apple.security.network.server</key>' not in text:
        raise SystemExit(
            f'{relative} lacks com.apple.security.network.server. '
            'Run ./scripts/bootstrap.sh again.'
        )
print('macOS network.server entitlement: OK')
PY

flutter pub get
flutter build macos --release

echo
echo "Build complete:"
echo "$ROOT/build/macos/Build/Products/Release/"
