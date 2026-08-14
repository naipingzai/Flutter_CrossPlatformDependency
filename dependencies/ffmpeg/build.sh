#!/usr/bin/env bash
# ============================================================
# build.sh - FFmpeg 跨平台静态库构建（自包含）
# ============================================================
# 本脚本完全独立，不依赖仓库内任何其他脚本。每个依赖目录自带一份
# 完整 build.sh，互不耦合：新增/修改某个库不会影响其他库。
#
# 平台相关值（ARCH / CC / SYSROOT / EXTRA_CFLAGS 等）由
# .github/workflows/build_ffmpeg.yml 通过环境变量注入。
#
# 用法：bash dependencies/ffmpeg/build.sh
# ============================================================
set -euo pipefail

# ============================================================
# 【规则 A】依赖常量 —— 新增库时只需修改本段
# ============================================================
DEP_NAME="ffmpeg"
DEP_VERSION="7.1"
# 优先使用 GitHub 镜像（比 ffmpeg.org 更稳定，避免 CI 下载被重置）
DEP_TARBALL="ffmpeg-${DEP_VERSION}.tar.gz"
DEP_URL="https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n7.1.tar.gz"
DEP_SRC_DIR="FFmpeg-n7.1"

# 源码 / 产物暂存目录（默认在 runner temp，可被 workflow 覆盖）
DEP_SOURCE_ROOT="${DEP_SOURCE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-src}"
DEP_STAGE_ROOT="${DEP_STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-stage}"

# 本库自身的 configure 参数（精简掉用不到的组件）
DEP_CONFIGURE_FLAGS="
--disable-network
--disable-avdevice
--disable-postproc
--disable-encoders
--disable-filters
--disable-muxers
--disable-bsfs
--disable-indevs
--disable-outdevs
--enable-pic"

# ============================================================
# 【规则 B】平台规则 —— 目标 OS 与交叉编译开关
# ============================================================
# 目标 OS 名（传给 --target-os）
platform_target_os() {
  case "${PLATFORM:?未设置 PLATFORM}" in
    linux)   echo "linux" ;;
    windows) echo "mingw32" ;;
    macos)   echo "darwin" ;;
    android) echo "android" ;;
    ios)     echo "darwin" ;;
    *)       echo "[${DEP_NAME}] 未知平台: ${PLATFORM}" >&2; exit 1 ;;
  esac
}

# 是否需要交叉编译（0/1）
platform_needs_cross() {
  case "$PLATFORM" in
    macos|android|ios) echo 1 ;;
    *) echo 0 ;;
  esac
}

# ============================================================
# 【规则 C】下载规则 —— 下载并解压源码（已存在则跳过）
# ============================================================
fetch_source() {
  mkdir -p "${DEP_SOURCE_ROOT}"
  if [ -d "${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}" ]; then
    echo "[${DEP_NAME}] 源码已存在，跳过下载"
    return
  fi
  echo "[${DEP_NAME}] 下载 ${DEP_URL}"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 5 --retry-delay 3 --retry-all-errors \
         --connect-timeout 20 -o "${DEP_SOURCE_ROOT}/${DEP_TARBALL}" "${DEP_URL}"
  else
    wget --tries=5 -O "${DEP_SOURCE_ROOT}/${DEP_TARBALL}" "${DEP_URL}"
  fi
  # Windows(MSYS) 下把 Windows 路径转成 unix 路径给 tar 用
  local t p
  if command -v cygpath >/dev/null 2>&1; then
    t="$(cygpath -u "${DEP_SOURCE_ROOT}/${DEP_TARBALL}")"
    p="$(cygpath -u "${DEP_SOURCE_ROOT}")"
  else
    t="${DEP_SOURCE_ROOT}/${DEP_TARBALL}"; p="${DEP_SOURCE_ROOT}"
  fi
  if ! tar -xJf "$t" -C "$p" 2>/dev/null; then
    tar -xzf "$t" -C "$p"
  fi
  echo "[${DEP_NAME}] 源码就绪: ${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}"
}

# ============================================================
# 【规则 D】构建规则 —— configure / make / install
# ============================================================
build() {
  local target_os cross
  target_os="$(platform_target_os)"
  cross="$(platform_needs_cross)"

  local inst="${DEP_STAGE_ROOT}/install-${PLATFORM}-${ARCH}"
  rm -rf "$inst"
  local bd="${DEP_SOURCE_ROOT}/build-${PLATFORM}-${ARCH}"
  mkdir -p "$bd" && cd "$bd"

  local cfg=()
  cfg+=(--prefix="$inst")
  cfg+=(--enable-static --disable-shared)   # 静态库
  cfg+=(--disable-programs --disable-doc --disable-debug)
  cfg+=($DEP_CONFIGURE_FLAGS)
  cfg+=(--arch="${ARCH}" --target-os="${target_os}")
  if [ "$cross" = "1" ]; then cfg+=(--enable-cross-compile); fi
  if [ -n "${CC:-}" ];        then cfg+=(--cc="${CC}"); fi
  if [ -n "${CXX:-}" ];       then cfg+=(--cxx="${CXX}"); fi
  if [ -n "${CROSS_PREFIX:-}" ]; then cfg+=(--cross-prefix="${CROSS_PREFIX}"); fi
  if [ -n "${SYSROOT:-}" ];   then cfg+=(--sysroot="${SYSROOT}"); fi
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cfg+=(--extra-cflags="${EXTRA_CFLAGS}"); fi
  if [ -n "${EXTRA_LDFLAGS:-}" ]; then cfg+=(--extra-ldflags="${EXTRA_LDFLAGS}"); fi
  # iOS 关闭内联汇编
  if [ "$PLATFORM" = "ios" ]; then cfg+=(--disable-asm); fi

  echo "[${DEP_NAME}] configure: ${cfg[*]}"
  "${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}/configure" "${cfg[@]}"
  make -j"$(platform_jobs)"
  make install
}

# 并行编译进程数
platform_jobs() {
  if command -v nproc >/dev/null 2>&1; then echo "$(nproc)";
  else echo "$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"; fi
}

# ============================================================
# 【规则 E】产物整理规则 —— 输出到统一结构
#   ${DEP_STAGE_ROOT}/${DEP_NAME}/${PLAT_OUT}/${ARCH_DIR}/{include,lib}
# ============================================================
stage_output() {
  local plat_out="${DEP_PLAT_OUT:-${PLATFORM}}"
  local arch_dir="${ARCH_DIR:-${ARCH}}"
  local out="${DEP_STAGE_ROOT}/${DEP_NAME}/${plat_out}/${arch_dir}"
  rm -rf "$out"; mkdir -p "$out"
  cp -a "${DEP_STAGE_ROOT}/install-${PLATFORM}-${ARCH}/include" "$out/include"
  cp -a "${DEP_STAGE_ROOT}/install-${PLATFORM}-${ARCH}/lib"     "$out/lib"
  rm -f "$out"/lib/pkgconfig/*.pc 2>/dev/null || true
  echo "[${DEP_NAME}] 已产出: ${out}"
}

# ============================================================
# 执行
# ============================================================
fetch_source
build
stage_output
echo "[${DEP_NAME}] ${PLATFORM}/${ARCH:-?} 构建完成"
