#!/usr/bin/env bash
# ============================================================
# libs/ffmpeg.sh —— FFmpeg 编译（autoconf）
# 需要环境变量：PLATFORM, ARCH, ARCH_DIR, CC, AR, SYSROOT(可选),
#               EXTRA_CFLAGS(可选), EXTRA_LDFLAGS(可选), CROSS_PREFIX(可选)
# ============================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common/functions.sh"

build_ffmpeg() {
  local DEP_SRC_DIR="FFmpeg-${FFMPEG_VERSION}"
  dl_extract ffmpeg "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/${FFMPEG_VERSION}.tar.gz" "$DEP_SRC_DIR" "ffmpeg.tar.gz"

  local target_os cross
  target_os="$(platform_target_os)"
  cross="$(platform_needs_cross)"

  local inst="${STAGE_ROOT}/ffmpeg-inst"
  rm -rf "$inst"

  local bd="${SRC_ROOT}/ffmpeg/build"
  mkdir -p "$bd" && cd "$bd"

  local cfg=()
  cfg+=(--prefix="$inst")
  cfg+=(--enable-static --enable-shared)
  cfg+=(--disable-programs --disable-doc --disable-debug)
  cfg+=($FFMPEG_COMMON_FLAGS)
  cfg+=(--arch="${ARCH}" --target-os="${target_os}")

  if [ "$cross" = "1" ]; then cfg+=(--enable-cross-compile); fi
  if [ -n "${CC:-}" ]; then cfg+=(--cc="${CC}"); fi
  if [ -n "${CXX:-}" ]; then cfg+=(--cxx="${CXX}"); fi
  if [ -n "${AR:-}" ]; then cfg+=(--ar="${AR}"); fi
  if [ -n "${CROSS_PREFIX:-}" ]; then cfg+=(--cross-prefix="${CROSS_PREFIX}"); fi
  # Android NDK llvm-ar 同时替代 ar 和 ranlib
  if [ "$PLATFORM" = "android" ] && [ -n "${AR:-}" ]; then
    cfg+=(--ranlib="${AR}")
  fi
  if [ -n "${SYSROOT:-}" ]; then cfg+=(--sysroot="${SYSROOT}"); fi
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cfg+=(--extra-cflags="${EXTRA_CFLAGS}"); fi
  if [ -n "${EXTRA_LDFLAGS:-}" ]; then cfg+=(--extra-ldflags="${EXTRA_LDFLAGS}"); fi
  if [ "$PLATFORM" = "ios" ]; then cfg+=(--disable-asm); fi

  "${SRC_ROOT}/ffmpeg/${DEP_SRC_DIR}/configure" "${cfg[@]}"
  make -j"$(platform_jobs)"
  make install

  stage_lib ffmpeg
  cp -a "$inst/include" "${STAGE_ROOT}/ffmpeg/${PLATFORM}/${ARCH_DIR}/include"
  cp -a "$inst/lib" "${STAGE_ROOT}/ffmpeg/${PLATFORM}/${ARCH_DIR}/lib"
  rm -f "${STAGE_ROOT}/ffmpeg/${PLATFORM}/${ARCH_DIR}"/lib/pkgconfig/*.pc 2>/dev/null || true

  # Android PIC 校验
  if [ "$PLATFORM" = "android" ]; then
    for lib_file in "${STAGE_ROOT}/ffmpeg/${PLATFORM}/${ARCH_DIR}/lib"/*.a; do
      [ -f "$lib_file" ] || continue
      android_check_pic "$lib_file"
    done
  fi

  echo "[ffmpeg] 完成（静态库 + 动态库）"
}

build_ffmpeg
