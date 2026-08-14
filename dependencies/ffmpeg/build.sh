#!/usr/bin/env bash
# ============================================================
# build.sh - FFmpeg 构建入口（平台无关）
# ============================================================
# 用法（由 workflow 注入平台环境变量后调用）：
#   bash dependencies/ffmpeg/build.sh
#
# 平台相关参数（ARCH/CC/SYSROOT/EXTRA_CFLAGS 等）由
# .github/workflows/build_ffmpeg.yml 注入，通用逻辑在 scripts/common.sh。
# 若需新增依赖，复制本目录结构并修改 DEP_* 常量与 CONFIGURE_FLAGS 即可。
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/common.sh"

# ---------- FFmpeg 依赖常量 ----------
export DEP_NAME="ffmpeg"
DEP_VERSION="7.1"
export DEP_TARBALL="ffmpeg-${DEP_VERSION}.tar.xz"
export DEP_URL="https://ffmpeg.org/releases/${DEP_TARBALL}"
export DEP_SRC_DIR="ffmpeg-${DEP_VERSION}"
export DEP_STATIC="1"

# 源码/stage 目录（可由 workflow 覆盖，默认用 runner temp）
export DEP_SOURCE_ROOT="${DEP_SOURCE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-src}"
export DEP_STAGE_ROOT="${DEP_STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-stage}"
export DEP_OUTPUT_DIR="${DEP_NAME}"

# ---------- FFmpeg 精简 configure 参数（去掉用不到的组件） ----------
export CONFIGURE_FLAGS="\
--disable-network \
--disable-avdevice \
--disable-postproc \
--disable-encoders \
--disable-filters \
--disable-muxers \
--disable-bsfs \
--disable-indevs \
--disable-outdevs \
--enable-pic"

# ---------- 执行 ----------
dep_fetch_source
dep_build
dep_stage_output
echo "[${DEP_NAME}] ${PLATFORM}/${ARCH} 构建完成"
