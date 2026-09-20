#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -d macos ]; then
  echo "macos runner missing. Run ./scripts/bootstrap.sh first."
  exit 1
fi

flutter pub get
flutter run -d macos
