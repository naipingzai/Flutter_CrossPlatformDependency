#!/usr/bin/env bash
# ============================================================
# Linux x86_64 —— 自包含构建：ffmpeg / miniz / stb_image / sqlite / python
# 各库构建函数照抄自 per-tool 已验证脚本（规则 A-E），仅做平台编排与合并。
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PLATFORM=linux ARCH=x86_64 ARCH_DIR=x86_64
export SRC_ROOT="${SRC_ROOT:-${RUNNER_TEMP:-/tmp}/deps-src}"
export STAGE_ROOT="${STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/deps-stage}"

# ---- 通用 ----
dl_extract() { # $1=dep $2=url $3=src_dir $4=tarball
  local dep="$1" url="$2" src_dir="$3" tarball="$4"
  local root="${SRC_ROOT}/${dep}"
  if [ -d "${root}/${src_dir}" ]; then echo "[${dep}] 源码已存在"; return; fi
  mkdir -p "${root}"
  curl -fL --retry 5 --retry-delay 3 --retry-all-errors -o "${root}/${tarball}" "${url}"
  # Windows(MSYS) 下把 Windows 路径转 unix 给 tar
  local t p
  if command -v cygpath >/dev/null 2>&1; then
    t="$(cygpath -u "${root}/${tarball}")"; p="$(cygpath -u "${root}")"
  else
    t="${root}/${tarball}"; p="${root}"
  fi
  tar -xzf "$t" -C "$p"
  echo "[${dep}] 就绪: ${root}/${src_dir}"
}
platform_cc()  { echo "${CC:-cc}"; }
platform_ar()  { echo "${AR:-ar}"; }
platform_jobs() { if command -v nproc >/dev/null 2>&1; then echo "$(nproc)"; else echo "$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"; fi; }
platform_target_os() { case "$PLATFORM" in linux) echo linux;; windows) echo mingw32;; macos) echo darwin;; android) echo android;; ios) echo darwin;; esac; }
platform_needs_cross() { case "$PLATFORM" in macos|android|ios) echo 1;; *) echo 0;; esac; }

# 各库产物统一 stage 到 ${STAGE_ROOT}/<lib>/<PLATFORM>/<ARCH_DIR>/{include,lib}
stage_lib() { local lib="$1"; local out="${STAGE_ROOT}/${lib}/${PLATFORM}/${ARCH_DIR}"; rm -rf "$out"; mkdir -p "$out"; }

# ============================================================
# ffmpeg（autoconf）—— 照抄 dependencies/ffmpeg/build.sh
# ============================================================
build_ffmpeg() {
  local DEP_NAME=ffmpeg DEP_SRC_DIR=FFmpeg-n7.1 DEP_CONFIGURE_FLAGS="--disable-network --disable-avdevice --disable-postproc --disable-encoders --disable-filters --disable-muxers --disable-bsfs --disable-indevs --disable-outdevs --enable-pic"
  dl_extract ffmpeg "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n7.1.tar.gz" "$DEP_SRC_DIR" "ffmpeg.tar.gz"
  local target_os cross
  target_os="$(platform_target_os)"; cross="$(platform_needs_cross)"
  local inst="${STAGE_ROOT}/ffmpeg-inst"; rm -rf "$inst"
  local bd="${SRC_ROOT}/ffmpeg/build"; mkdir -p "$bd" && cd "$bd"
  local cfg=()
  cfg+=(--prefix="$inst"); cfg+=(--enable-static --disable-shared)
  cfg+=(--disable-programs --disable-doc --disable-debug); cfg+=($DEP_CONFIGURE_FLAGS)
  cfg+=(--arch="${ARCH}" --target-os="${target_os}")
  if [ "$cross" = "1" ]; then cfg+=(--enable-cross-compile); fi
  if [ -n "${CC:-}" ]; then cfg+=(--cc="${CC}"); fi
  if [ -n "${CXX:-}" ]; then cfg+=(--cxx="${CXX}"); fi
  if [ -n "${CROSS_PREFIX:-}" ]; then cfg+=(--cross-prefix="${CROSS_PREFIX}"); fi
  if [ -n "${SYSROOT:-}" ]; then cfg+=(--sysroot="${SYSROOT}"); fi
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cfg+=(--extra-cflags="${EXTRA_CFLAGS}"); fi
  if [ -n "${EXTRA_LDFLAGS:-}" ]; then cfg+=(--extra-ldflags="${EXTRA_LDFLAGS}"); fi
  if [ "$PLATFORM" = "ios" ]; then cfg+=(--disable-asm); fi
  "${SRC_ROOT}/ffmpeg/${DEP_SRC_DIR}/configure" "${cfg[@]}"
  make -j"$(platform_jobs)"; make install
  stage_lib ffmpeg
  cp -a "$inst/include" "${STAGE_ROOT}/ffmpeg/${PLATFORM}/${ARCH_DIR}/include"
  cp -a "$inst/lib" "${STAGE_ROOT}/ffmpeg/${PLATFORM}/${ARCH_DIR}/lib"
  rm -f "${STAGE_ROOT}/ffmpeg/${PLATFORM}/${ARCH_DIR}"/lib/pkgconfig/*.pc 2>/dev/null || true
  echo "[ffmpeg] 完成"
}

# ============================================================
# miniz（直接编译）—— 照抄 dependencies/miniz/build.sh
# ============================================================
build_miniz() {
  local DEP_SRC_DIR=miniz-2.2.0 DEP_SOURCES="miniz.c miniz_zip.c miniz_tdef.c miniz_tinfl.c" DEP_HEADERS="miniz.h miniz_common.h miniz_export.h miniz_tdef.h miniz_tinfl.h miniz_zip.h"
  dl_extract miniz "https://github.com/richgel999/miniz/archive/refs/tags/2.2.0.tar.gz" "$DEP_SRC_DIR" "miniz.tar.gz"
  local cc ar; cc="$(platform_cc)"; ar="$(platform_ar)"
  local src="${SRC_ROOT}/miniz/${DEP_SRC_DIR}"
  if [ ! -f "${src}/miniz_export.h" ]; then printf '#pragma once\n#define MINIZ_EXPORT\n' > "${src}/miniz_export.h"; fi
  local inst="${STAGE_ROOT}/miniz-inst"; rm -rf "$inst"; mkdir -p "$inst/include" "$inst/lib"
  local bd="${SRC_ROOT}/miniz/build"; rm -rf "$bd"; mkdir -p "$bd"
  local cflags=(-O2 -fPIC -I"${src}")
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cflags+=($EXTRA_CFLAGS); fi
  if [ -n "${SYSROOT:-}" ]; then cflags+=("-isysroot" "${SYSROOT}"); fi
  local objs=()
  for s in $DEP_SOURCES; do local o="${bd}/${s%.c}.o"; "${cc}" "${cflags[@]}" -c "${src}/${s}" -o "$o"; objs+=("$o"); done
  ${ar} rcs "$inst/lib/libminiz.a" "${objs[@]}"
  for h in $DEP_HEADERS; do cp "${src}/${h}" "$inst/include/${h}"; done
  stage_lib miniz
  cp -a "$inst/include" "${STAGE_ROOT}/miniz/${PLATFORM}/${ARCH_DIR}/include"
  cp -a "$inst/lib" "${STAGE_ROOT}/miniz/${PLATFORM}/${ARCH_DIR}/lib"
  echo "[miniz] 完成"
}

# ============================================================
# stb_image（直接编译）—— 照抄 dependencies/stb_image/build.sh
# ============================================================
build_stb_image() {
  local DEP_SRC_DIR=stb-master
  dl_extract stb_image "https://github.com/nothings/stb/archive/refs/heads/master.tar.gz" "$DEP_SRC_DIR" "stb.tar.gz"
  local cc ar; cc="$(platform_cc)"; ar="$(platform_ar)"
  local src="${SRC_ROOT}/stb_image/${DEP_SRC_DIR}"
  local inst="${STAGE_ROOT}/stb_image-inst"; rm -rf "$inst"; mkdir -p "$inst/include" "$inst/lib"
  local bd="${SRC_ROOT}/stb_image/build"; rm -rf "$bd"; mkdir -p "$bd"
  printf '#define STB_IMAGE_IMPLEMENTATION\n#include "stb_image.h"\n' > "${bd}/stb_image.c"
  local cflags=(-O2 -fPIC -I"${src}")
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cflags+=($EXTRA_CFLAGS); fi
  if [ -n "${SYSROOT:-}" ]; then cflags+=("-isysroot" "${SYSROOT}"); fi
  "${cc}" "${cflags[@]}" -c "${bd}/stb_image.c" -o "${bd}/stb_image.o"
  ${ar} rcs "$inst/lib/libstb_image.a" "$bd/stb_image.o"
  cp "${src}/stb_image.h" "$inst/include/stb_image.h"
  stage_lib stb_image
  cp -a "$inst/include" "${STAGE_ROOT}/stb_image/${PLATFORM}/${ARCH_DIR}/include"
  cp -a "$inst/lib" "${STAGE_ROOT}/stb_image/${PLATFORM}/${ARCH_DIR}/lib"
  echo "[stb_image] 完成"
}

# ============================================================
# sqlite（直接编译 amalgamation）—— 照抄 dependencies/sqlite/build.sh
# ============================================================
build_sqlite() {
  local DEP_SRC_DIR=sqlite-autoconf-3460100
  dl_extract sqlite "https://www.sqlite.org/2024/sqlite-autoconf-3460100.tar.gz" "$DEP_SRC_DIR" "sqlite.tar.gz"
  local cc ar; cc="$(platform_cc)"; ar="$(platform_ar)"
  local src="${SRC_ROOT}/sqlite/${DEP_SRC_DIR}"
  local inst="${STAGE_ROOT}/sqlite-inst"; rm -rf "$inst"; mkdir -p "$inst/include" "$inst/lib"
  local bd="${SRC_ROOT}/sqlite/build"; rm -rf "$bd"; mkdir -p "$bd"
  local cflags=(-O2 -fPIC)
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cflags+=($EXTRA_CFLAGS); fi
  if [ -n "${SYSROOT:-}" ]; then cflags+=("-isysroot" "${SYSROOT}"); fi
  "${cc}" "${cflags[@]}" -c "${src}/sqlite3.c" -o "$bd/sqlite3.o"
  ${ar} rcs "$inst/lib/libsqlite3.a" "$bd/sqlite3.o"
  cp "${src}/sqlite3.h" "$inst/include/sqlite3.h"; cp "${src}/sqlite3ext.h" "$inst/include/sqlite3ext.h"
  stage_lib sqlite
  cp -a "$inst/include" "${STAGE_ROOT}/sqlite/${PLATFORM}/${ARCH_DIR}/include"
  cp -a "$inst/lib" "${STAGE_ROOT}/sqlite/${PLATFORM}/${ARCH_DIR}/lib"
  echo "[sqlite] 完成"
}

# ============================================================
# python（autoconf 原生）—— 照抄 dependencies/python/build.sh
# ============================================================

build_python() {
  local DEP_SRC_DIR=cpython-3.12.7
  dl_extract python "https://github.com/python/cpython/archive/refs/tags/v3.12.7.tar.gz" "$DEP_SRC_DIR" "cpython.tar.gz"
  local inst="${STAGE_ROOT}/python-inst"; rm -rf "$inst"
  local bd="${SRC_ROOT}/python/build-${PLATFORM}-${ARCH}"; rm -rf "$bd"; mkdir -p "$bd" && cd "$bd"
  "${SRC_ROOT}/python/${DEP_SRC_DIR}/configure" --prefix="$inst" \
    --without-ensurepip --disable-shared --without-doc-strings --disable-test-modules \
    || { echo "==== [python] configure 失败，完整 config.log ===="; cat "${bd}/config.log" 2>/dev/null || true; echo "==== config.log 结束 ===="; exit 1; }
  make -j"$(platform_jobs)"; make install
  stage_lib python
  local out="${STAGE_ROOT}/python/${PLATFORM}/${ARCH_DIR}"
  cp -a "$inst/include" "$out/include"
  cp -a "$inst/lib" "$out/lib"
  # 严格检查：静态库 + 头文件必须真实存在，否则视为构建失败
  [ -f "$out/lib/libpython3.12.a" ] || { echo "[python] 错误：未生成 libpython3.12.a" >&2; exit 1; }
  [ -f "$out/include/python3.12/Python.h" ] || { echo "[python] 错误：未生成 Python.h" >&2; exit 1; }
  echo "[python] 完成（已通过严格检查）"
}

# ============================================================
# 合并
# ============================================================
stage_platform() {
  local out="${STAGE_ROOT}/${PLATFORM}/${ARCH_DIR}"
  rm -rf "$out"; mkdir -p "$out/include" "$out/lib"
  for dep in ffmpeg miniz stb_image sqlite python; do
    local d="${STAGE_ROOT}/${dep}/${PLATFORM}/${ARCH_DIR}"
    [ -d "$d" ] || continue
    cp -a "$d/include/." "$out/include/" 2>/dev/null || true
    cp -a "$d/lib/." "$out/lib/" 2>/dev/null || true
  done
  echo "[platform] 合并完成: ${out}"
}

build_ffmpeg; build_miniz; build_stb_image; build_sqlite; build_python
stage_platform
echo "[linux] 全部构建完成"
