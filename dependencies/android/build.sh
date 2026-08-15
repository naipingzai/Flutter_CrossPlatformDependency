#!/usr/bin/env bash
# ============================================================
# ANDROID —— 自包含构建：ffmpeg / miniz / stb_image / sqlite / python
# 目标：Android arm64-v8a（API 21+，NDK 交叉编译）
#
# 背景说明（务必阅读）：
#   本仓库把 FFmpeg 等第三方库编译为「静态库 .a」。APP（Flutter_FileManager）
#   在 Android 上通过 DynamicLibrary.open('libfileops.so') 加载原生代码，
#   因此会把 libnative.a（含 FFmpeg）打包进一个共享库壳 libfileops.so。
#   共享库（.so）在 ARM64 上强制要求所有代码为位置无关（PIC），
#   所以 Android 的 FFmpeg 静态库必须带 -fPIC，否则链接 .so 时报
#   "R_AARCH64_ADR_PREL_PG_HI21 ... recompile with -fPIC"。
#
#   这正是 Android 与桌面（Linux/macOS/Windows 直接静态链接进可执行文件、
#   无需 PIC）的关键差异。iOS 同样静态链接，但由 Apple 签名打包，无需本脚本干预。
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- 必配环境变量（由 .github/workflows/build_platforms.yml 的 android Job 注入）----
# PLATFORM  目标平台标识（本文件固定为 android，勿改）
# ARCH      目标 CPU 架构（本文件固定为 aarch64，勿改）
# ARCH_DIR  产物目录名（本文件固定为 arm64-v8a，勿改）
# CC        交叉编译器，如 $NDK/.../bin/aarch64-linux-android21-clang（必填）
# AR        归档器，如 $NDK/.../bin/llvm-ar（必填）
# SYSROOT   NDK sysroot，如 $NDK/.../toolchains/.../sysroot（可选）
# EXTRA_CFLAGS  追加 CFLAGS，如 "-DANDROID -fPIC"（可选，务必含 -fPIC）
# EXTRA_LDFLAGS 追加 LDFLAGS（可选）
export PLATFORM=android ARCH=aarch64 ARCH_DIR=arm64-v8a
export SRC_ROOT="${SRC_ROOT:-${RUNNER_TEMP:-/tmp}/deps-src}"
export STAGE_ROOT="${STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/deps-stage}"
CC="${CC:?需要 CC}"; AR="${AR:?需要 AR}"; export CC AR; SYSROOT="${SYSROOT:-}"; export SYSROOT; EXTRA_CFLAGS="${EXTRA_CFLAGS:-}"; export EXTRA_CFLAGS; EXTRA_LDFLAGS="${EXTRA_LDFLAGS:-}"; export EXTRA_LDFLAGS
# 各库构建函数照抄自 per-tool 已验证脚本（规则 A-E），仅做平台编排与合并。
# ============================================================
set -euo pipefail

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
# ffmpeg（autoconf）
# 产物：libavformat.a libavcodec.a libavutil.a libswscale.a libswresample.a
# ------------------------------------------------------------
# 可调配置项：
#   DEP_SRC_DIR            FFmpeg 源码目录名（版本 tag 对应）
#   DEP_CONFIGURE_FLAGS    减裁开关：去掉网络/设备/编码器/滤镜/封装器等，
#                          + --enable-pic（Android 必须，见头部说明）
#   url                    源码下载地址（版本 tag 需与 DEP_SRC_DIR 一致）
# 若换 FFmpeg 版本：同步改 DEP_SRC_DIR、url、以及 APP 侧头文件即可。
# ============================================================
build_ffmpeg() {
  # 版本 7.1（tag n7.1）
  local DEP_SRC_DIR=FFmpeg-n7.1
  local DEP_CONFIGURE_FLAGS="--disable-network --disable-avdevice --disable-postproc --disable-encoders --disable-filters --disable-muxers --disable-bsfs --disable-indevs --disable-outdevs --enable-pic"
  dl_extract ffmpeg "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n7.1.tar.gz" "$DEP_SRC_DIR" "ffmpeg.tar.gz"
  local target_os cross
  target_os="$(platform_target_os)"; cross="$(platform_needs_cross)"
  local inst="${STAGE_ROOT}/ffmpeg-inst"; rm -rf "$inst"
  local bd="${SRC_ROOT}/ffmpeg/build"; mkdir -p "$bd" && cd "$bd"
  local cfg=()
  # 静态库、裁剪掉命令行工具/文档/调试符号
  cfg+=(--prefix="$inst"); cfg+=(--enable-static --disable-shared)
  cfg+=(--disable-programs --disable-doc --disable-debug); cfg+=($DEP_CONFIGURE_FLAGS)
  # 目标架构 / 目标 OS / 交叉编译（android 需要）
  cfg+=(--arch="${ARCH}" --target-os="${target_os}")
  if [ "$cross" = "1" ]; then cfg+=(--enable-cross-compile); fi
  # 工具链：编译器 / C++ / 交叉前缀 / sysroot
  if [ -n "${CC:-}" ]; then cfg+=(--cc="${CC}"); fi
  if [ -n "${CXX:-}" ]; then cfg+=(--cxx="${CXX}"); fi
  if [ -n "${CROSS_PREFIX:-}" ]; then cfg+=(--cross-prefix="${CROSS_PREFIX}"); fi
  if [ -n "${SYSROOT:-}" ]; then cfg+=(--sysroot="${SYSROOT}"); fi
  # 追加编译/链接参数（EXTRA_CFLAGS 必须含 -fPIC，见 workflow 注入）
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cfg+=(--extra-cflags="${EXTRA_CFLAGS}"); fi
  if [ -n "${EXTRA_LDFLAGS:-}" ]; then cfg+=(--extra-ldflags="${EXTRA_LDFLAGS}"); fi
  # iOS 无汇编加速需要，Android 保留 asm（neon）
  if [ "$PLATFORM" = "ios" ]; then cfg+=(--disable-asm); fi
  # Android 静态库会被链接进共享库 libfileops.so，必须生成 PIC。
  # --enable-pic 已含于 DEP_CONFIGURE_FLAGS，且 workflow 已传 EXTRA_CFLAGS="-DANDROID -fPIC"，
  # 二者足以让 FFmpeg 的 C 与汇编均为 PIC。此处不做任何 make 参数覆盖，避免破坏头文件搜索路径。
  "${SRC_ROOT}/ffmpeg/${DEP_SRC_DIR}/configure" "${cfg[@]}"
  make -j"$(platform_jobs)"; make install
  # 严格校验：所有目标文件必须为 PIC（不得出现非 PIC 的 ADR_PREL_PG_HI21 重定位）。
  if command -v llvm-readelf >/dev/null 2>&1; then
    local nonpic=0
    for o in "$bd"/libav*/*.o; do
      [ -f "$o" ] || continue
      if llvm-readelf -r "$o" 2>/dev/null | grep -q "R_AARCH64_ADR_PREL_PG_HI21"; then nonpic=$((nonpic+1)); fi
    done
    if [ "$nonpic" -gt 0 ]; then
      echo "[ffmpeg] 错误：仍有 ${nonpic} 个对象非 PIC" >&2; exit 1
    fi
    echo "[ffmpeg] PIC 校验通过"
  fi
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



build_python() {
  local DEP_SRC_DIR=cpython-3.12.7
  dl_extract python "https://github.com/python/cpython/archive/refs/tags/v3.12.7.tar.gz" "$DEP_SRC_DIR" "cpython.tar.gz"
  local inst="${STAGE_ROOT}/python-inst"; rm -rf "$inst"
  local bd="${SRC_ROOT}/python/build-${PLATFORM}-${ARCH}"; rm -rf "$bd"; mkdir -p "$bd" && cd "$bd"
  local cfg=(--prefix="$inst" --without-ensurepip --disable-shared --without-doc-strings --disable-test-modules)
  # 交叉编译：HOST_TRIPLE / BUILD_PYTHON 必须由 workflow 注入，否则明确报错
  if [ -z "${HOST_TRIPLE:-}" ]; then
    echo "[python] 错误：Android 交叉编译需要 HOST_TRIPLE" >&2; exit 1
  fi
  if [ -z "${BUILD_PYTHON:-}" ]; then
    echo "[python] 错误：Android 交叉编译需要 BUILD_PYTHON（与目标同版本的主机 python）" >&2; exit 1
  fi
  cfg+=(--host="${HOST_TRIPLE}" --build="${BUILD_TRIPLE:-$(uname -m)-linux-gnu}")
  # 交叉编译时 getaddrinfo 运行时测试无法执行，需关闭 IPv6
  cfg+=(--disable-ipv6)
  # 交叉编译时无法探测 /dev 设备文件，用 CONFIG_SITE 预置结果
  # Android(bionic) 缺失部分外部库/头文件，禁用依赖它们的 stdlib C 模块：
  #   grp/spwd       无组/影子密码数据库
  #   _ctypes        libffi 头文件未配置进编译路径
  #   ossaudiodev    OSS 音频设备在 Android 不可用
  #   _lzma/_bz2    Android NDK sysroot 无 liblzma/libbz2 头文件
  #   readline       Android 无 GNU readline
  #   _ssl/_hashlib  Android NDK 无 OpenSSL
  local site="${SRC_ROOT}/config-${PLATFORM}.site"
  printf 'ac_cv_file__dev_ptmx=yes
ac_cv_file__dev_ptc=no
py_cv_module_grp=n/a
py_cv_module_spwd=n/a
py_cv_module__ctypes=n/a
py_cv_module_ossaudiodev=n/a
py_cv_module__lzma=n/a
py_cv_module__bz2=n/a
py_cv_module_readline=n/a
py_cv_module__ssl=n/a
py_cv_module__hashlib=n/a
' > "$site"
  export CONFIG_SITE="$site"
  cfg+=(--with-build-python="${BUILD_PYTHON}")
  [ -n "${CC:-}" ] && export CC; [ -n "${CXX:-}" ] && export CXX
  [ -n "${AR:-}" ] && export AR; [ -n "${RANLIB:-}" ] && export RANLIB; [ -n "${STRIP:-}" ] && export STRIP
  [ -n "${SYSROOT:-}" ] && export CFLAGS="${CFLAGS:-} --sysroot=${SYSROOT}"
  [ -n "${EXTRA_CFLAGS:-}" ] && export CFLAGS="${CFLAGS:-} ${EXTRA_CFLAGS}"
  [ -n "${EXTRA_LDFLAGS:-}" ] && export LDFLAGS="${LDFLAGS:-} ${EXTRA_LDFLAGS}"
  echo "[python] configure: ${cfg[*]}"
  if ! "${SRC_ROOT}/python/${DEP_SRC_DIR}/configure" "${cfg[@]}"; then
    echo "==== [python] configure 失败，完整 config.log ===="
    cat "${bd}/config.log" 2>/dev/null || true
    echo "==== config.log 结束 ===="
    exit 1
  fi
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
