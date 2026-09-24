#!/usr/bin/env bash

set -Eeuo pipefail

PACKAGE_ROOT="${PACKAGE_ROOT:-smb-packages}"
REMOTE_BASE="${SMB_REMOTE_BASE:-Log4App}"

: "${SMB_SERVER:?SMB_SERVER is required}"
: "${SMB_SHARE:?SMB_SHARE is required}"
: "${SMB_USER:?SMB_USER is required}"
: "${SMB_PASS:?SMB_PASS is required}"

VERSION="${SMB_VERSION:-}"

if [ -z "$VERSION" ]; then
    VERSION="$(
        sed -n \
            's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' \
            pubspec.yaml |
        head -n 1
    )"
fi

if [ -z "$VERSION" ]; then
    echo "ERROR: Unable to determine application version."
    exit 1
fi

VERSION="${VERSION#v}"
VERSION_DIR="v${VERSION}"

REMOTE_VERSION_ROOT="${REMOTE_BASE}/${VERSION_DIR}"
SMB_TARGET="//${SMB_SERVER}/${SMB_SHARE}"

WINDOWS_DIR="${PACKAGE_ROOT}/windows"
MACOS_DIR="${PACKAGE_ROOT}/macos-arm64"
LINUX_X64_DIR="${PACKAGE_ROOT}/linux-x64"
LINUX_ARM64_DIR="${PACKAGE_ROOT}/linux-arm64"

AUTH_FILE=""

cleanup() {
    local exit_code=$?

    if [ -n "${AUTH_FILE:-}" ] && [ -f "$AUTH_FILE" ]; then
        rm -f "$AUTH_FILE"
    fi

    exit "$exit_code"
}

trap cleanup EXIT


if ! command -v smbclient >/dev/null 2>&1; then
    echo "ERROR: smbclient is not installed."
    exit 1
fi


verify_directory() {
    local directory="$1"
    local platform="$2"

    if [ ! -d "$directory" ]; then
        echo "ERROR: Missing artifact directory."
        echo "Platform : $platform"
        echo "Directory: $directory"
        exit 1
    fi

    if ! find "$directory" -type f -print -quit | grep -q .; then
        echo "ERROR: No artifact found."
        echo "Platform : $platform"
        echo "Directory: $directory"
        exit 1
    fi
}


verify_directory "$WINDOWS_DIR" "Windows x64"
verify_directory "$MACOS_DIR" "macOS ARM64"
verify_directory "$LINUX_X64_DIR" "Linux x64"
verify_directory "$LINUX_ARM64_DIR" "Linux ARM64"


echo
echo "========================================"
echo "Log4App SMB Publisher"
echo "========================================"
echo "Version    : $VERSION"
echo "Target     : $SMB_TARGET"
echo "Remote dir : $REMOTE_VERSION_ROOT"


AUTH_FILE="$(mktemp)"
chmod 600 "$AUTH_FILE"

cat > "$AUTH_FILE" <<EOF
username = $SMB_USER
password = $SMB_PASS
EOF


echo
echo "Testing SMB connection..."

smbclient \
    "$SMB_TARGET" \
    -A "$AUTH_FILE" \
    -m SMB3 \
    -c "ls" \
    >/dev/null

echo "SMB connection OK."


ensure_directory() {
    local parent="$1"
    local directory="$2"

    if [ -z "$parent" ]; then
        smbclient \
            "$SMB_TARGET" \
            -A "$AUTH_FILE" \
            -m SMB3 \
            -c "mkdir \"$directory\"" \
            >/dev/null 2>&1 || true
    else
        smbclient \
            "$SMB_TARGET" \
            -A "$AUTH_FILE" \
            -m SMB3 \
            -c "cd \"$parent\"; mkdir \"$directory\"" \
            >/dev/null 2>&1 || true
    fi
}


ensure_directory "" "$REMOTE_BASE"
ensure_directory "$REMOTE_BASE" "$VERSION_DIR"

ensure_directory "$REMOTE_VERSION_ROOT" "windows"
ensure_directory "$REMOTE_VERSION_ROOT" "macos-arm64"
ensure_directory "$REMOTE_VERSION_ROOT" "linux-x64"
ensure_directory "$REMOTE_VERSION_ROOT" "linux-arm64"


upload_directory() {
    local local_dir="$1"
    local remote_platform_dir="$2"
    local platform="$3"

    local uploaded=0

    echo
    echo "========================================"
    echo "Publishing $platform"
    echo "========================================"

    while IFS= read -r -d '' file
    do
        local filename
        local local_path
        local temp_filename

        filename="$(basename "$file")"
        local_path="$(cd "$(dirname "$file")" && pwd)"

        temp_filename=".${filename}.uploading.$$"

        echo "Uploading: $filename"

        smbclient \
            "$SMB_TARGET" \
            -A "$AUTH_FILE" \
            -m SMB3 \
            -c "
                cd \"$REMOTE_VERSION_ROOT\";
                cd \"$remote_platform_dir\";
                lcd \"$local_path\";
                put \"$filename\" \"$temp_filename\";
            "

        smbclient \
            "$SMB_TARGET" \
            -A "$AUTH_FILE" \
            -m SMB3 \
            -c "
                cd \"$REMOTE_VERSION_ROOT\";
                cd \"$remote_platform_dir\";
                del \"$filename\";
            " \
            >/dev/null 2>&1 || true

        smbclient \
            "$SMB_TARGET" \
            -A "$AUTH_FILE" \
            -m SMB3 \
            -c "
                cd \"$REMOTE_VERSION_ROOT\";
                cd \"$remote_platform_dir\";
                rename \"$temp_filename\" \"$filename\";
            "

        uploaded=$((uploaded + 1))

    done < <(
        find "$local_dir" \
            -maxdepth 1 \
            -type f \
            -print0
    )

    if [ "$uploaded" -eq 0 ]; then
        echo "ERROR: No files uploaded for $platform."
        exit 1
    fi

    echo "$platform: $uploaded file(s) uploaded."
}


upload_directory "$WINDOWS_DIR" "windows" "Windows x64"
upload_directory "$MACOS_DIR" "macos-arm64" "macOS ARM64"
upload_directory "$LINUX_X64_DIR" "linux-x64" "Linux x64"
upload_directory "$LINUX_ARM64_DIR" "linux-arm64" "Linux ARM64"


verify_remote_directory() {
    local remote_platform="$1"
    local platform="$2"

    echo
    echo "Verify: $platform"

    smbclient \
        "$SMB_TARGET" \
        -A "$AUTH_FILE" \
        -m SMB3 \
        -c "
            cd \"$REMOTE_VERSION_ROOT\";
            cd \"$remote_platform\";
            ls;
        "
}


verify_remote_directory "windows" "Windows x64"
verify_remote_directory "macos-arm64" "macOS ARM64"
verify_remote_directory "linux-x64" "Linux x64"
verify_remote_directory "linux-arm64" "Linux ARM64"


SMB_DIRECTORY="${SMB_TARGET}/${REMOTE_VERSION_ROOT}"

echo
echo "========================================"
echo "SMB publish completed successfully"
echo "========================================"
echo "Version : $VERSION"
echo "Path    : $SMB_DIRECTORY"


if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "version=$VERSION"
        echo "smb_directory=$SMB_DIRECTORY"
    } >> "$GITHUB_OUTPUT"
fi