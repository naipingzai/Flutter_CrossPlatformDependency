#!/usr/bin/env bash
# ============================================================
# build_linux.sh - 编译 Linux x86_64 静态库
# ============================================================
# 在 ubuntu-24.04 runner 上执行。使用宿主 gcc 编译 x86_64。
# 产出：${STAGE_ROOT}/ffmpeg/linux/x86_64/{include,lib}
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

build_x86_64() {
  echo "[ffmpeg] ==== 构建 Linux x86_64 ===="
  export STAGE_INSTALL="${STAGE_ROOT}/install-linux-x86_64"
  rm -rf "${STAGE_INSTALL}"
  local build_dir="${FFMPEG_SOURCE_ROOT}/build-linux-x86_64"
  mkdir -p "${build_dir}" && cd "${build_dir}"
  "${FFMPEG_SOURCE_ROOT}/${FFMPEG_SRC_DIR}/configure" \
    $(ffmpeg_common_config) \
    --arch=x86_64 \
    --cc=gcc \
    --cxx=g++ \
    --target-os=linux
  make $(ffmpeg_make_flags)
  make install
  ffmpeg_stage_output "linux" "x86_64"
}

ffmpeg_fetch_source
build_x86_64
echo "[ffmpeg] Linux 构建完成"
