#!/bin/bash

set -euo pipefail

PACKAGE_ROOT="${PACKAGE_ROOT:-smb-packages}"
REMOTE_BASE="${SMB_REMOTE_BASE:-Log4App}"

: "${SMB_SERVER:?SMB_SERVER is required}"
: "${SMB_SHARE:?SMB_SHARE is required}"
: "${SMB_USER:?SMB_USER is required}"
: "${SMB_PASS:?SMB_PASS is required}"

WINDOWS_DIR="$PACKAGE_ROOT/windows"
MACOS_DIR="$PACKAGE_ROOT/macos-arm64"
LINUX_X64_DIR="$PACKAGE_ROOT/linux-x64"
LINUX_ARM64_DIR="$PACKAGE_ROOT/linux-arm64"

SMB_URL="smb://${SMB_SERVER}/${SMB_SHARE}"
MOUNT_POINT=""
MOUNTED_BY_SCRIPT="false"

cleanup() {
    local exit_code=$?

    echo
    echo "========================================"
    echo "Cleanup"
    echo "========================================"

    if [ "$MOUNTED_BY_SCRIPT" = "true" ] && [ -n "$MOUNT_POINT" ]; then
        echo "Unmount SMB: $MOUNT_POINT"
        diskutil unmount "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi

    if [ -d "$PACKAGE_ROOT" ]; then
        echo "Remove downloaded artifacts: $PACKAGE_ROOT"
        rm -rf "$PACKAGE_ROOT"
    fi

    exit "$exit_code"
}

trap cleanup EXIT

verify_directory() {
    local directory="$1"
    local platform="$2"

    if [ ! -d "$directory" ]; then
        echo "ERROR: Missing $platform artifact directory: $directory" >&2
        exit 1
    fi

    if ! find "$directory" -type f -print -quit | grep -q .; then
        echo "ERROR: No package found for $platform in: $directory" >&2
        exit 1
    fi
}

sha256_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

copy_packages() {
    local source="$1"
    local destination="$2"
    local platform="$3"
    local copied=0

    echo
    echo "----------------------------------------"
    echo "Publishing $platform"
    echo "Source      : $source"
    echo "Destination : $destination"
    echo "----------------------------------------"

    mkdir -p "$destination"

    while IFS= read -r -d '' file; do
        local basename
        local temp_file
        local final_file
        local local_sha
        local remote_sha

        basename="$(basename "$file")"
        temp_file="$destination/.${basename}.uploading.$$"
        final_file="$destination/$basename"

        echo "Upload: $basename"

        rm -f "$temp_file"
        cp -f "$file" "$temp_file"

        local_sha="$(sha256_file "$file")"
        remote_sha="$(sha256_file "$temp_file")"

        if [ "$local_sha" != "$remote_sha" ]; then
            echo "ERROR: SHA256 mismatch after uploading $basename" >&2
            echo "Local : $local_sha" >&2
            echo "Remote: $remote_sha" >&2
            rm -f "$temp_file"
            exit 1
        fi

        mv -f "$temp_file" "$final_file"

        echo "Verified: $local_sha"
        copied=$((copied + 1))
    done < <(find "$source" -type f -print0)

    if [ "$copied" -eq 0 ]; then
        echo "ERROR: No files were copied for $platform" >&2
        exit 1
    fi

    echo "Published $copied file(s) for $platform."
}

echo "========================================"
echo "Log4App SMB Publisher"
echo "========================================"
echo "SMB server : $SMB_SERVER"
echo "SMB share  : $SMB_SHARE"
echo "Remote base: $REMOTE_BASE"
echo "Package dir: $PACKAGE_ROOT"

verify_directory "$WINDOWS_DIR" "Windows x64"
verify_directory "$MACOS_DIR" "macOS ARM64"
verify_directory "$LINUX_X64_DIR" "Linux x64"
verify_directory "$LINUX_ARM64_DIR" "Linux ARM64"

echo
echo "Artifacts ready for publishing:"
find "$PACKAGE_ROOT" -type f -print

echo
echo "Mounting SMB share..."

export SMB_URL SMB_USER SMB_PASS

MOUNT_POINT="$(osascript <<'APPLESCRIPT'
set smbUrl to system attribute "SMB_URL"
set smbUser to system attribute "SMB_USER"
set smbPass to system attribute "SMB_PASS"

tell application "Finder"
    set mountedVolume to mount volume smbUrl as user name smbUser with password smbPass
end tell

return POSIX path of mountedVolume
APPLESCRIPT
)"

MOUNT_POINT="${MOUNT_POINT%/}"
MOUNTED_BY_SCRIPT="true"

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    echo "ERROR: SMB mount failed. Mount point: $MOUNT_POINT" >&2
    exit 1
fi

echo "Mounted at: $MOUNT_POINT"

REMOTE_ROOT="$MOUNT_POINT/$REMOTE_BASE"
REMOTE_WINDOWS="$REMOTE_ROOT/windows"
REMOTE_MACOS="$REMOTE_ROOT/macos-arm64"
REMOTE_LINUX_X64="$REMOTE_ROOT/linux-x64"
REMOTE_LINUX_ARM64="$REMOTE_ROOT/linux-arm64"

mkdir -p \
    "$REMOTE_WINDOWS" \
    "$REMOTE_MACOS" \
    "$REMOTE_LINUX_X64" \
    "$REMOTE_LINUX_ARM64"

copy_packages "$WINDOWS_DIR" "$REMOTE_WINDOWS" "Windows x64"
copy_packages "$MACOS_DIR" "$REMOTE_MACOS" "macOS ARM64"
copy_packages "$LINUX_X64_DIR" "$REMOTE_LINUX_X64" "Linux x64"
copy_packages "$LINUX_ARM64_DIR" "$REMOTE_LINUX_ARM64" "Linux ARM64"

echo
echo "========================================"
echo "SMB publish completed successfully"
echo "========================================"
echo "Remote root: $REMOTE_ROOT"
echo "Local temporary artifacts will be removed during cleanup."
