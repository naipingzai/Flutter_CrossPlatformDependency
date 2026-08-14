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
# 注意：
#   - 每个架构构建前必须设置 STAGE_INSTALL 为独立前缀，避免并发冲突。
#   - 必须在 build_* 中先调用 ffmpeg_fetch_source() 下载源码。
# ============================================================

set -euo pipefail

FFMPEG_VERSION="7.1"
FFMPEG_TARBALL="ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_URL="https://ffmpeg.org/releases/${FFMPEG_TARBALL}"
FFMPEG_SRC_DIR="ffmpeg-${FFMPEG_VERSION}"

# 源码下载/解压目录
FFMPEG_SOURCE_ROOT="${FFMPEG_SOURCE_ROOT:-${RUNNER_TEMP:-/tmp}/ffmpeg-src}"

# staging 目录（脚本最终把 include/lib 放到这里，由 workflow 打包）
STAGE_ROOT="${STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/ffmpeg-stage}"

# 当前架构的 install 前缀（由 build_* 设置为 ${STAGE_ROOT}/install-<arch>）
STAGE_INSTALL="${STAGE_INSTALL:-${STAGE_ROOT}/install}"

# ============================================================
# 工具：Windows(MSYS) 下把 Windows 路径转成 unix 路径（/d/...）
# 原生 bash 工具（tar 等）不识别 D:/ 形式
# ============================================================
msys_unix_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1"
  else
    echo "$1"
  fi
}

# ============================================================
# 下载并解压 FFmpeg 源码（已存在则跳过）
# ============================================================
ffmpeg_fetch_source() {
  mkdir -p "${FFMPEG_SOURCE_ROOT}"
  if [ ! -d "${FFMPEG_SOURCE_ROOT}/${FFMPEG_SRC_DIR}" ]; then
    echo "[ffmpeg] 下载 ${FFMPEG_URL}"
    if command -v curl >/dev/null 2>&1; then
      curl -fL --retry 3 --retry-delay 3 -o "${FFMPEG_SOURCE_ROOT}/${FFMPEG_TARBALL}" "${FFMPEG_URL}"
    else
      wget -O "${FFMPEG_SOURCE_ROOT}/${FFMPEG_TARBALL}" "${FFMPEG_URL}"
    fi
    local tarball_ux tarball_parent_ux
    tarball_ux="$(msys_unix_path "${FFMPEG_SOURCE_ROOT}/${FFMPEG_TARBALL}")"
    tarball_parent_ux="$(msys_unix_path "${FFMPEG_SOURCE_ROOT}")"
    tar -xJf "${tarball_ux}" -C "${tarball_parent_ux}"
  fi
  echo "[ffmpeg] 源码就绪: ${FFMPEG_SOURCE_ROOT}/${FFMPEG_SRC_DIR}"
}

# ============================================================
# 精简 configure 基础参数（各平台在此基础上追加 --target-os/--cc 等）
# ============================================================
ffmpeg_common_config() {
  echo "--prefix=${STAGE_INSTALL}"
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

# ============================================================
# 并行编译参数
# ============================================================
ffmpeg_make_flags() {
  local nproc
  if command -v nproc >/dev/null 2>&1; then
    nproc="$(nproc)"
  else
    nproc="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"
  fi
  echo "-j${nproc}"
}

# ============================================================
# 编译并整理产物：把 ${STAGE_INSTALL}/include 与 lib 复制到
# ${STAGE_ROOT}/ffmpeg/<plat>/<arch>/
# 用法：ffmpeg_stage_output <plat> <arch>
# ============================================================
ffmpeg_stage_output() {
  local plat="$1"; local arch="$2"
  local out="${STAGE_ROOT}/ffmpeg/${plat}/${arch}"
  rm -rf "${out}"
  mkdir -p "${out}"
  cp -a "${STAGE_INSTALL}/include" "${out}/include"
  cp -a "${STAGE_INSTALL}/lib"     "${out}/lib"
  # 删除无用的 pc/pkg-config 文件，保持产物精简
  rm -f "${out}"/lib/pkgconfig/*.pc 2>/dev/null || true
  echo "[ffmpeg] 已产出: ${out}"
}
