#!/usr/bin/env bash
# ============================================================
# platforms/windows.sh —— Windows (MSYS2/MinGW) 平台配置
# ============================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common/functions.sh"

PLATFORM="windows"
export PLATFORM

export ARCH="x86_64"
export ARCH_DIR="x86_64"

# MSYS2 MinGW 工具链
export CROSS_PREFIX="x86_64-w64-mingw32-"
export CC="${CROSS_PREFIX}gcc"
export CXX="${CROSS_PREFIX}g++"
export AR="${CROSS_PREFIX}ar"
unset SYSROOT EXTRA_CFLAGS EXTRA_LDFLAGS HOST_TRIPLE BUILD_PYTHON 2>/dev/null || true

DEPS_TO_BUILD="${LIBS_LIST:-ffmpeg miniz stb_image sqlite python}"
for lib in $DEPS_TO_BUILD; do
  echo "========== 编译 ${lib} (Windows ${ARCH}) =========="
  bash "$(dirname "${BASH_SOURCE[0]}")/../libs/${lib}.sh"
done

stage_platform
python_check "$(platform_cc)"
stage_release
