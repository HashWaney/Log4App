#!/usr/bin/env bash

set -Eeuo pipefail

PACKAGE_ROOT="${PACKAGE_ROOT:-smb-packages}"
REMOTE_BASE="${NEXUS_REMOTE_BASE:-Log4App}"

: "${NEXUS_URL:?NEXUS_URL is required}"
: "${NEXUS_REPO:?NEXUS_REPO is required}"
: "${NEXUS_USER:?NEXUS_USER is required}"
: "${NEXUS_PASS:?NEXUS_PASS is required}"

NEXUS_URL="${NEXUS_URL%/}"

VERSION="${NEXUS_VERSION:-}"

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

WINDOWS_DIR="${PACKAGE_ROOT}/windows"
MACOS_DIR="${PACKAGE_ROOT}/macos-arm64"
LINUX_X64_DIR="${PACKAGE_ROOT}/linux-x64"
LINUX_ARM64_DIR="${PACKAGE_ROOT}/linux-arm64"


verify_directory() {
    local directory="$1"
    local platform="$2"

    if [ ! -d "$directory" ]; then
        echo "ERROR: Missing directory: $directory"
        echo "Platform: $platform"
        exit 1
    fi

    if ! find "$directory" -type f -print -quit | grep -q .; then
        echo "ERROR: No files for $platform."
        exit 1
    fi
}


verify_directory "$WINDOWS_DIR" "Windows x64"
verify_directory "$MACOS_DIR" "macOS ARM64"
verify_directory "$LINUX_X64_DIR" "Linux x64"
verify_directory "$LINUX_ARM64_DIR" "Linux ARM64"


REPORT_FILE="$(mktemp)"

cleanup() {
    rm -f "$REPORT_FILE"
}

trap cleanup EXIT


upload_file() {
    local file="$1"
    local remote_platform="$2"

    local filename
    local remote_dir
    local download_url
    local response_file
    local http_code
    local verify_code
    local size
    local sha256

    filename="$(basename "$file")"

    remote_dir="${REMOTE_BASE}/${VERSION_DIR}/${remote_platform}"

    download_url="${NEXUS_URL}/repository/${NEXUS_REPO}/${remote_dir}/${filename}"

    size="$(du -h "$file" | awk '{print $1}')"
    sha256="$(sha256sum "$file" | awk '{print $1}')"

    response_file="$(mktemp)"

    echo
    echo "========================================"
    echo "Upload Nexus"
    echo "========================================"
    echo "File : $filename"
    echo "Size : $size"
    echo "Dir  : $remote_dir"

    http_code="$(
        curl \
            --silent \
            --show-error \
            --write-out "%{http_code}" \
            --output "$response_file" \
            --connect-timeout 15 \
            --max-time 600 \
            --noproxy "*" \
            --user "$NEXUS_USER:$NEXUS_PASS" \
            --request POST \
            --form "raw.asset1=@${file}" \
            --form "raw.asset1.filename=${filename}" \
            --form "raw.directory=${remote_dir}" \
            "${NEXUS_URL}/service/rest/v1/components?repository=${NEXUS_REPO}"
    )"

    if [ "$http_code" != "201" ] &&
       [ "$http_code" != "204" ]; then

        echo "ERROR: Nexus upload failed."
        echo "HTTP: $http_code"

        cat "$response_file"
        rm -f "$response_file"

        exit 1
    fi

    rm -f "$response_file"

    echo "Uploaded successfully: HTTP $http_code"

    echo "Verifying: $download_url"

    verify_code="$(
        curl \
            --silent \
            --show-error \
            --output /dev/null \
            --write-out "%{http_code}" \
            --connect-timeout 15 \
            --max-time 120 \
            --noproxy "*" \
            --user "$NEXUS_USER:$NEXUS_PASS" \
            "$download_url"
    )"

    if [ "$verify_code" != "200" ]; then
        echo "ERROR: Nexus verification failed."
        echo "HTTP: $verify_code"
        echo "URL : $download_url"
        exit 1
    fi

    echo "Verified: $download_url"

    {
        echo "- [$filename]($download_url)"
        echo "  - 大小：$size"
        echo "  - SHA256：\`$sha256\`"
    } >> "$REPORT_FILE"
}


upload_platform() {
    local directory="$1"
    local platform="$2"
    local remote_platform="$3"

    echo >> "$REPORT_FILE"
    echo "#### $platform" >> "$REPORT_FILE"
    echo >> "$REPORT_FILE"

    while IFS= read -r -d '' file
    do
        upload_file "$file" "$remote_platform"

    done < <(
        find "$directory" \
            -maxdepth 1 \
            -type f \
            -print0
    )
}


echo "========================================"
echo "Log4App Nexus Publisher"
echo "========================================"
echo "Version    : $VERSION"
echo "Repository : $NEXUS_REPO"


upload_platform "$WINDOWS_DIR" "Windows x64" "windows"
upload_platform "$MACOS_DIR" "macOS ARM64" "macos-arm64"
upload_platform "$LINUX_X64_DIR" "Linux x64" "linux-x64"
upload_platform "$LINUX_ARM64_DIR" "Linux ARM64" "linux-arm64"


NEXUS_ROOT_URL="${NEXUS_URL}/repository/${NEXUS_REPO}/${REMOTE_BASE}/${VERSION_DIR}/"

echo
echo "========================================"
echo "Nexus publish completed successfully"
echo "========================================"
echo "Version : $VERSION"
echo "URL     : $NEXUS_ROOT_URL"

cat "$REPORT_FILE"


if [ -n "${GITHUB_OUTPUT:-}" ]; then

    delimiter="NEXUS_MARKDOWN_$(date +%s%N)"

    {
        echo "version=$VERSION"
        echo "nexus_root_url=$NEXUS_ROOT_URL"

        echo "package_markdown<<$delimiter"
        cat "$REPORT_FILE"
        echo "$delimiter"

    } >> "$GITHUB_OUTPUT"
fi