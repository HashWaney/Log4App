#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:9090}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Log4App V2.1 smoke test"
echo "Server: $BASE_URL"
echo

echo "[1/4] GET /api/server/info"
curl --fail --silent --show-error "$BASE_URL/api/server/info"
echo
echo

echo "[2/4] POST /api/device/ping"
curl --fail --silent --show-error \
  -X POST \
  -H 'Content-Type: application/json' \
  -d '{"deviceId":"TEST_001","deviceName":"Smoke Test Device","appVersion":"1.0.0","platform":"Test","platformVersion":"1.0"}' \
  "$BASE_URL/api/device/ping"
echo
echo

echo "test log from Log4App smoke test" > "$TMP_DIR/app.log"
(
  cd "$TMP_DIR"
  if command -v zip >/dev/null 2>&1; then
    zip -q test.zip app.log
  else
    cp app.log test.zip
  fi
)

echo "[3/4] POST /api/log/upload"
curl --fail --silent --show-error \
  -X POST \
  -F 'deviceId=TEST_001' \
  -F 'deviceName=Smoke Test Device' \
  -F 'appVersion=1.0.0' \
  -F 'platform=Test' \
  -F 'platformVersion=1.0' \
  -F "file=@$TMP_DIR/test.zip" \
  "$BASE_URL/api/log/upload"
echo
echo

echo "[4/4] GET /api/device/list"
curl --fail --silent --show-error "$BASE_URL/api/device/list"
echo
echo

echo "PASS: server info, device ping, upload and device list all responded successfully."
