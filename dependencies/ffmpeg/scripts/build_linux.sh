#!/usr/bin/env bash
# ============================================================
# build_linux.sh - 编译 Linux 静态库 (x86_64 / aarch64)
# ============================================================
# 在 ubuntu-24.04 runner 上执行。使用宿主 gcc 编译。
# 产出：${STAGE_ROOT}/ffmpeg/linux/<arch>/{include,lib}
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# aarch64 需要交叉编译器
install_cross() {
  if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    return
  fi
  echo "[ffmpeg] 安装 aarch64 交叉编译器"
  sudo apt-get update
  sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
}

build_arch() {
  local arch="$1"
  local cc="gcc"
  local cxx="g++"
  local extra=()
  if [ "$arch" = "aarch64" ]; then
    cc="aarch64-linux-gnu-gcc"
    cxx="aarch64-linux-gnu-g++"
    extra+=(--enable-cross-compile --arch=aarch64 --target-os=linux)
  fi
  echo "[ffmpeg] ==== 构建 Linux ${arch} ===="
  rm -rf "${STAGE_ROOT}/install"
  local build_dir="${FFMPEG_SOURCE_ROOT}/build-linux-${arch}"
  mkdir -p "${build_dir}"
  # 在源码目录外单独 configure，便于多 arch 并行产物隔离
  mkdir -p "${build_dir}" && cd "${build_dir}"
  "${FFMPEG_SOURCE_ROOT}/${FFMPEG_SRC_DIR}/configure" \
    $(ffmpeg_common_config) \
    --arch="${arch}" \
    --cc="${cc}" \
    --cxx="${cxx}" \
    --target-os=linux \
    "${extra[@]}"
  make $(ffmpeg_make_flags)
  make install
  ffmpeg_stage_output "linux" "${arch}"
}

# 并行构建两个架构
install_cross
build_arch "x86_64" &
build_arch "aarch64" &
wait
echo "[ffmpeg] Linux 构建完成"
