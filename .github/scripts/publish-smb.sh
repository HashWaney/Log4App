#!/usr/bin/env bash

set -Eeuo pipefail


# ============================================================
# Log4App SMB Publisher
#
# GitHub Actions Self-hosted Linux Runner
#
# 最终目录：
#
# share/
# └── Log4App/
#     └── v2.10.4/
#         ├── windows/
#         ├── macos-arm64/
#         ├── linux-x64/
#         └── linux-arm64/
#
# ============================================================


# ============================================================
# 基础配置
# ============================================================

PACKAGE_ROOT="${PACKAGE_ROOT:-smb-packages}"
REMOTE_BASE="${SMB_REMOTE_BASE:-Log4App}"

: "${SMB_SERVER:?SMB_SERVER is required}"
: "${SMB_SHARE:?SMB_SHARE is required}"
: "${SMB_USER:?SMB_USER is required}"
: "${SMB_PASS:?SMB_PASS is required}"


# ============================================================
# 获取应用版本
#
# 优先级：
#
# 1. SMB_VERSION
# 2. pubspec.yaml
#
# 例如：
#
# version: 2.10.4+104
#
# 得到：
#
# VERSION=2.10.4
# VERSION_DIR=v2.10.4
#
# ============================================================

VERSION="${SMB_VERSION:-}"

if [ -z "$VERSION" ]; then

    if [ ! -f "pubspec.yaml" ]; then
        echo "ERROR: pubspec.yaml not found."
        exit 1
    fi

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


# 如果传入 v2.10.4，去掉前面的 v，
# 后面统一生成 VERSION_DIR。
VERSION="${VERSION#v}"

VERSION_DIR="v${VERSION}"

REMOTE_VERSION_ROOT="${REMOTE_BASE}/${VERSION_DIR}"


# ============================================================
# SMB
# ============================================================

SMB_TARGET="//${SMB_SERVER}/${SMB_SHARE}"


# ============================================================
# Artifact 本地目录
# ============================================================

WINDOWS_DIR="${PACKAGE_ROOT}/windows"
MACOS_DIR="${PACKAGE_ROOT}/macos-arm64"
LINUX_X64_DIR="${PACKAGE_ROOT}/linux-x64"
LINUX_ARM64_DIR="${PACKAGE_ROOT}/linux-arm64"


AUTH_FILE=""


# ============================================================
# Cleanup
# ============================================================

cleanup() {

    local exit_code=$?

    echo
    echo "========================================"
    echo "Cleanup"
    echo "========================================"

    # 删除临时 SMB 凭据
    if [ -n "${AUTH_FILE:-}" ] && [ -f "$AUTH_FILE" ]; then

        echo "Removing temporary SMB credential file..."

        rm -f "$AUTH_FILE"
    fi


    # 删除 GitHub Actions 下载的安装包
    if [ -d "$PACKAGE_ROOT" ]; then

        echo "Removing downloaded artifacts:"
        echo "$PACKAGE_ROOT"

        rm -rf "$PACKAGE_ROOT"
    fi


    echo "Cleanup completed."

    exit "$exit_code"
}


trap cleanup EXIT


# ============================================================
# 检查依赖
# ============================================================

if ! command -v smbclient >/dev/null 2>&1; then

    echo "ERROR: smbclient is not installed."
    echo
    echo "Install it on the self-hosted runner:"
    echo
    echo "sudo apt update"
    echo "sudo apt install -y smbclient"

    exit 1
fi


# ============================================================
# Artifact 校验
# ============================================================

verify_directory() {

    local directory="$1"
    local platform="$2"

    if [ ! -d "$directory" ]; then

        echo "ERROR: Missing artifact directory."
        echo
        echo "Platform : $platform"
        echo "Directory: $directory"

        exit 1
    fi


    if ! find "$directory" -type f -print -quit | grep -q .; then

        echo "ERROR: No artifact found."
        echo
        echo "Platform : $platform"
        echo "Directory: $directory"

        exit 1
    fi
}


verify_directory \
    "$WINDOWS_DIR" \
    "Windows x64"

verify_directory \
    "$MACOS_DIR" \
    "macOS ARM64"

verify_directory \
    "$LINUX_X64_DIR" \
    "Linux x64"

verify_directory \
    "$LINUX_ARM64_DIR" \
    "Linux ARM64"


# ============================================================
# 打印发布信息
# ============================================================

echo
echo "========================================"
echo "Log4App SMB Publisher"
echo "========================================"

echo "Version     : $VERSION"
echo "Version dir : $VERSION_DIR"

echo "SMB server  : $SMB_SERVER"
echo "SMB share   : $SMB_SHARE"

echo "Remote base : $REMOTE_BASE"
echo "Remote dir  : $REMOTE_VERSION_ROOT"

echo "Package dir : $PACKAGE_ROOT"


echo
echo "========================================"
echo "Artifacts ready for publishing"
echo "========================================"

find "$PACKAGE_ROOT" \
    -type f \
    -print


# ============================================================
# 创建 SMB credential 临时文件
#
# 不使用：
#
# smbclient -U user%password
#
# 避免密码出现在命令行 / ps 中。
# ============================================================

AUTH_FILE="$(mktemp)"

chmod 600 "$AUTH_FILE"

cat > "$AUTH_FILE" <<EOF
username = $SMB_USER
password = $SMB_PASS
EOF


# ============================================================
# 测试 SMB 网络与登录
# ============================================================

echo
echo "========================================"
echo "Testing SMB connection"
echo "========================================"

echo "Target:"
echo "$SMB_TARGET"


smbclient \
    "$SMB_TARGET" \
    -A "$AUTH_FILE" \
    -m SMB3 \
    -c "ls" \
    >/dev/null


echo "SMB connection OK."


# ============================================================
# 创建远端目录
# ============================================================

create_remote_dir() {

    local remote_dir="$1"

    echo "Ensure remote directory:"
    echo "$remote_dir"

    # 目录已经存在时 mkdir 可能返回错误，
    # 所以这里允许失败。
    smbclient \
        "$SMB_TARGET" \
        -A "$AUTH_FILE" \
        -m SMB3 \
        -c "mkdir \"$remote_dir\"" \
        >/dev/null 2>&1 || true
}


echo
echo "========================================"
echo "Preparing SMB directories"
echo "========================================"


# Log4App
create_remote_dir \
    "$REMOTE_BASE"


# Log4App/v2.10.4
create_remote_dir \
    "$REMOTE_VERSION_ROOT"


# Log4App/v2.10.4/windows
create_remote_dir \
    "$REMOTE_VERSION_ROOT/windows"


# Log4App/v2.10.4/macos-arm64
create_remote_dir \
    "$REMOTE_VERSION_ROOT/macos-arm64"


# Log4App/v2.10.4/linux-x64
create_remote_dir \
    "$REMOTE_VERSION_ROOT/linux-x64"


# Log4App/v2.10.4/linux-arm64
create_remote_dir \
    "$REMOTE_VERSION_ROOT/linux-arm64"


# ============================================================
# 上传单个平台目录
# ============================================================

upload_directory() {

    local local_dir="$1"
    local remote_platform_dir="$2"
    local platform="$3"

    local uploaded=0


    echo
    echo "========================================"
    echo "Publishing $platform"
    echo "========================================"

    echo "Local:"
    echo "$local_dir"

    echo
    echo "Remote:"
    echo "$REMOTE_VERSION_ROOT/$remote_platform_dir"


    while IFS= read -r -d '' file
    do

        local filename
        local local_path
        local temp_filename

        filename="$(basename "$file")"

        local_path="$(
            cd "$(dirname "$file")"
            pwd
        )"


        # 上传过程中先使用临时文件名，
        # 避免其他人下载到半个文件。
        temp_filename=".${filename}.uploading.$$"


        echo
        echo "Uploading:"
        echo "$filename"


        # ----------------------------------------------------
        # 上传临时文件
        # ----------------------------------------------------

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


        # ----------------------------------------------------
        # 临时文件 -> 正式文件
        #
        # 如果同版本重新发布：
        # 删除旧正式文件，再 rename。
        # ----------------------------------------------------

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


        echo "Uploaded:"
        echo "$filename"

        uploaded=$((uploaded + 1))


    done < <(
        find "$local_dir" \
            -type f \
            -print0
    )


    if [ "$uploaded" -eq 0 ]; then

        echo "ERROR: No files uploaded."

        echo "Platform:"
        echo "$platform"

        exit 1
    fi


    echo
    echo "Published successfully:"
    echo "$platform -> $uploaded file(s)"
}


# ============================================================
# Windows x64
# ============================================================

upload_directory \
    "$WINDOWS_DIR" \
    "windows" \
    "Windows x64"


# ============================================================
# macOS ARM64
# ============================================================

upload_directory \
    "$MACOS_DIR" \
    "macos-arm64" \
    "macOS ARM64"


# ============================================================
# Linux x64
# ============================================================

upload_directory \
    "$LINUX_X64_DIR" \
    "linux-x64" \
    "Linux x64"


# ============================================================
# Linux ARM64
# ============================================================

upload_directory \
    "$LINUX_ARM64_DIR" \
    "linux-arm64" \
    "Linux ARM64"


# ============================================================
# 最终验证
# ============================================================

verify_remote_directory() {

    local remote_platform_dir="$1"
    local platform="$2"

    echo
    echo "----------------------------------------"
    echo "$platform"
    echo "----------------------------------------"

    smbclient \
        "$SMB_TARGET" \
        -A "$AUTH_FILE" \
        -m SMB3 \
        -c "
            cd \"$REMOTE_VERSION_ROOT\";
            cd \"$remote_platform_dir\";
            ls;
        "
}


echo
echo "========================================"
echo "Verify uploaded packages"
echo "========================================"


verify_remote_directory \
    "windows" \
    "Windows x64"


verify_remote_directory \
    "macos-arm64" \
    "macOS ARM64"


verify_remote_directory \
    "linux-x64" \
    "Linux x64"


verify_remote_directory \
    "linux-arm64" \
    "Linux ARM64"


# ============================================================
# 完成
# ============================================================

echo
echo "========================================"
echo "SMB publish completed successfully"
echo "========================================"

echo
echo "Version:"
echo "$VERSION"

echo
echo "SMB directory:"
echo "${SMB_TARGET}/${REMOTE_VERSION_ROOT}"

echo
echo "Directory structure:"

echo "${REMOTE_VERSION_ROOT}/"
echo "├── windows/"
echo "├── macos-arm64/"
echo "├── linux-x64/"
echo "└── linux-arm64/"

echo
echo "Local downloaded artifacts will now be removed."