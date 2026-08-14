#!/usr/bin/env bash
# ============================================================
# build_linux.sh - 编译 Linux 静态库 (x86_64 / aarch64)
# ============================================================
# 在 ubuntu-24.04 runner 上执行。使用宿主 gcc 编译 x86_64，
# 用 aarch64-linux-gnu-* 交叉编译 aarch64。串行构建，每个架构
# 使用独立 STAGE_INSTALL 前缀，避免冲突。
# 产出：${STAGE_ROOT}/ffmpeg/linux/<arch>/{include,lib}
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

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
    extra+=(--enable-cross-compile --target-os=linux)
  fi
  echo "[ffmpeg] ==== 构建 Linux ${arch} ===="
  export STAGE_INSTALL="${STAGE_ROOT}/install-linux-${arch}"
  rm -rf "${STAGE_INSTALL}"
  local build_dir="${FFMPEG_SOURCE_ROOT}/build-linux-${arch}"
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

install_cross
ffmpeg_fetch_source
build_arch "x86_64"
build_arch "aarch64"
echo "[ffmpeg] Linux 构建完成"
