#!/usr/bin/env bash
# ============================================================
# platforms/ios.sh —— iOS 平台配置（arm64）
# ============================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common/functions.sh"

PLATFORM="ios"
export PLATFORM

export ARCH="arm64"
export ARCH_DIR="arm64"

# Xcode 工具链
IOS_MIN_VERSION="12.0"
export CC="$(xcrun --sdk iphoneos --find clang)"
export CXX="$(xcrun --sdk iphoneos --find clang++)"
export AR="$(xcrun --sdk iphoneos --find ar)"
export SYSROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
export EXTRA_CFLAGS="-arch arm64 -mios-version-min=${IOS_MIN_VERSION} -isysroot ${SYSROOT} -fembed-bitcode"
export EXTRA_LDFLAGS="-arch arm64 -mios-version-min=${IOS_MIN_VERSION} -isysroot ${SYSROOT}"
unset CROSS_PREFIX HOST_TRIPLE BUILD_PYTHON 2>/dev/null || true

DEPS_TO_BUILD="${LIBS_LIST:-ffmpeg miniz stb_image sqlite python}"
for lib in $DEPS_TO_BUILD; do
  echo "========== 编译 ${lib} (iOS ${ARCH}) =========="
  bash "$(dirname "${BASH_SOURCE[0]}")/../libs/${lib}.sh"
done

stage_platform
python_check "$(platform_cc)"
stage_release
