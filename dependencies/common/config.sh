#!/usr/bin/env bash
# ============================================================
# common/config.sh —— 全局配置
# ============================================================

# 仓库根目录
DEP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 源码与中间产物根目录
export SRC_ROOT="${SRC_ROOT:-${RUNNER_TEMP:-/tmp}/deps-src}"
export STAGE_ROOT="${STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/deps-stage}"

# 编译线程数
platform_jobs() {
  if command -v nproc >/dev/null 2>&1; then echo "$(nproc)"
  else echo "$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"; fi
}

# FFmpeg 通用配置参数（所有平台共享）
FFMPEG_COMMON_FLAGS="--disable-network --disable-avdevice --disable-postproc --disable-encoders --disable-filters --disable-muxers --disable-bsfs --disable-indevs --disable-outdevs --enable-pic"
FFMPEG_VERSION="n7.1"

# miniz
MINIZ_VERSION="2.2.0"
MINIZ_SOURCES="miniz.c miniz_zip.c miniz_tdef.c miniz_tinfl.c"
MINIZ_HEADERS="miniz.h miniz_common.h miniz_export.h miniz_tdef.h miniz_tinfl.h miniz_zip.h"

# sqlite
SQLITE_VERSION="3460100"

# python
PYTHON_VERSION="3.12.7"

# 依赖库列表
DEP_LIBS="ffmpeg miniz stb_image sqlite python"
