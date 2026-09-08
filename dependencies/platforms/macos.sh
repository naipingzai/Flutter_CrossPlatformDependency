#!/usr/bin/env bash
# ============================================================
# platforms/macos.sh —— macOS 平台配置（支持 arm64 + x86_64）
# ============================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common/functions.sh"

PLATFORM="macos"
export PLATFORM

MACOS_ARCHS="arm64 x86_64"
DEPS_TO_BUILD="${LIBS_LIST:-ffmpeg miniz stb_image sqlite python}"

for arch in $MACOS_ARCHS; do
  export ARCH="$arch"
  export ARCH_DIR="$arch"

  export CC="cc"
  export CXX="c++"
  export AR="ar"
  unset SYSROOT CROSS_PREFIX EXTRA_CFLAGS EXTRA_LDFLAGS HOST_TRIPLE BUILD_PYTHON 2>/dev/null || true

  for lib in $DEPS_TO_BUILD; do
    echo "========== 编译 ${lib} (macOS ${arch}) =========="
    bash "$(dirname "${BASH_SOURCE[0]}")/../libs/${lib}.sh"
  done

  stage_platform
  python_check "$(platform_cc)"
  stage_release
done
