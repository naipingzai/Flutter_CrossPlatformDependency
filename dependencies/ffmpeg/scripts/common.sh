#!/usr/bin/env bash
# ============================================================
# common.sh - FFmpeg 各平台构建共用逻辑
# ============================================================
# 提供：
#   - FFMPEG_VERSION / FFMPEG_SRC_DIR / FFMPEG_TARBALL
#   - 下载并解压 FFmpeg 源码
#   - 统一的精简 configure 参数
#   - 编译并把 include/lib 整理到 staging 目录
#
# 用法：在 build_*.sh 中 source 本文件。
# ============================================================

set -euo pipefail

FFMPEG_VERSION="7.1"
FFMPEG_TARBALL="ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_URL="https://ffmpeg.org/releases/${FFMPEG_TARBALL}"
FFMPEG_SRC_DIR="ffmpeg-${FFMPEG_VERSION}"

# 源码下载/解压目录（CI 已 cache 或每次重新获取）
FFMPEG_SOURCE_ROOT="${FFMPEG_SOURCE_ROOT:-${RUNNER_TEMP:-/tmp}/ffmpeg-src}"

# staging 目录（脚本最终把 include/lib 放到这里，由 workflow 打包）
STAGE_ROOT="${STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/ffmpeg-stage}"

# 下载并解压 FFmpeg 源码（已存在则跳过）
ffmpeg_fetch_source() {
  mkdir -p "${FFMPEG_SOURCE_ROOT}"
  if [ ! -d "${FFMPEG_SOURCE_ROOT}/${FFMPEG_SRC_DIR}" ]; then
    echo "[ffmpeg] 下载 ${FFMPEG_URL}"
    if command -v curl >/dev/null 2>&1; then
      curl -fL --retry 3 --retry-delay 3 -o "${FFMPEG_SOURCE_ROOT}/${FFMPEG_TARBALL}" "${FFMPEG_URL}"
    else
      wget -O "${FFMPEG_SOURCE_ROOT}/${FFMPEG_TARBALL}" "${FFMPEG_URL}"
    fi
    tar -xJf "${FFMPEG_SOURCE_ROOT}/${FFMPEG_TARBALL}" -C "${FFMPEG_SOURCE_ROOT}"
  fi
  echo "[ffmpeg] 源码就绪: ${FFMPEG_SOURCE_ROOT}/${FFMPEG_SRC_DIR}"
}

# 精简 configure 基础参数（各平台在此基础上追加 --target-os/--cc 等）
ffmpeg_common_config() {
  echo "--prefix=${STAGE_ROOT}/install"
  echo "--enable-static"
  echo "--disable-shared"
  echo "--disable-programs"
  echo "--disable-doc"
  echo "--disable-debug"
  echo "--disable-network"
  echo "--disable-avdevice"
  echo "--disable-postproc"
  echo "--disable-encoders"
  echo "--disable-filters"
  echo "--disable-muxers"
  echo "--disable-bsfs"
  echo "--disable-indevs"
  echo "--disable-outdevs"
  echo "--enable-pic"
}

# 并行编译参数
ffmpeg_make_flags() {
  local nproc
  if command -v nproc >/dev/null 2>&1; then
    nproc="$(nproc)"
  else
    nproc="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"
  fi
  echo "-j${nproc}"
}

# 编译并整理产物：把 install/include 与 install/lib 复制到
# ${STAGE_ROOT}/ffmpeg/<plat>/<arch>/
# 用法：ffmpeg_stage_output <plat> <arch>
ffmpeg_stage_output() {
  local plat="$1"; local arch="$2"
  local out="${STAGE_ROOT}/ffmpeg/${plat}/${arch}"
  rm -rf "${out}"
  mkdir -p "${out}"
  cp -a "${STAGE_ROOT}/install/include" "${out}/include"
  cp -a "${STAGE_ROOT}/install/lib"     "${out}/lib"
  # 删除无用的 pc/pkg-config 文件，保持产物精简
  rm -f "${out}"/lib/pkgconfig/*.pc 2>/dev/null || true
  echo "[ffmpeg] 已产出: ${out}"
}
