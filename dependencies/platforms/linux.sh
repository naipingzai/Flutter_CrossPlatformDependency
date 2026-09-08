#!/usr/bin/env bash
# ============================================================
# platforms/linux.sh —— Linux 平台配置
# ============================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common/functions.sh"

PLATFORM="linux"
export PLATFORM

# Linux 只编译 x86_64
export ARCH="x86_64"
export ARCH_DIR="x86_64"

# 原生编译工具链
export CC="cc"
export CXX="c++"
export AR="ar"
unset SYSROOT CROSS_PREFIX EXTRA_CFLAGS EXTRA_LDFLAGS HOST_TRIPLE BUILD_PYTHON 2>/dev/null || true

# 依次编译各库（尊重 LIBS_LIST 环境变量）
DEPS_TO_BUILD="${LIBS_LIST:-ffmpeg miniz stb_image sqlite python}"
for lib in $DEPS_TO_BUILD; do
  echo "========== 编译 ${lib} (Linux ${ARCH}) =========="
  bash "$(dirname "${BASH_SOURCE[0]}")/../libs/${lib}.sh"
done

# 发布各库（独立）
DEPS_TO_BUILD="${LIBS_LIST:-ffmpeg miniz stb_image sqlite python}"
for lib in $DEPS_TO_BUILD; do
  stage_release "$lib"
done
python_check "$(platform_cc)"
