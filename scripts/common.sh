#!/usr/bin/env bash
# ============================================================
# common.sh - 第三方依赖跨平台构建通用引擎（autoconf/configure 型）
# ============================================================
# 供 dependencies/<dep>/build.sh 复用。平台差异一律通过环境变量由
# workflow（YAML）注入，脚本内不做平台业务判断，从而：
#   1. 平台配置集中在 .github/workflows（清晰区分）
#   2. 新增依赖只需提供 dependencies/<dep>/build.sh + workflow 条目
#
# 依赖 build.sh 需导出的变量：
#   DEP_NAME         依赖名（决定产物目录，如 ffmpeg）
#   DEP_URL          源码归档 URL
#   DEP_TARBALL      归档文件名
#   DEP_SRC_DIR      解压后的源码目录名
#   DEP_STATIC       (可选) 1=静态库 0=动态库，默认 1
#   CONFIGURE_FLAGS  (可选) 依赖自身的 configure 参数
#
# workflow 注入的平台变量：
#   PLATFORM         linux | windows | macos | android | ios
#   ARCH             架构（x86_64 / arm64 / aarch64 ...）
#   ARCH_DIR         产物子目录名（Android ABI 名 / macos arch / 默认=ARCH）
#   CC / CXX / SYSROOT / CROSS_PREFIX / EXTRA_CFLAGS / EXTRA_LDFLAGS
#   PLAT_OUT         (可选) 产物平台目录名，默认=PLATFORM
# ============================================================

set -euo pipefail

# ================= 路径工具（Windows MSYS 需 cygpath） =================
msys_unix_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else echo "$1"; fi
}

# ================= 源码下载/解压 =================
dep_fetch_source() {
  mkdir -p "${DEP_SOURCE_ROOT}"
  if [ ! -d "${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}" ]; then
    echo "[${DEP_NAME}] 下载 ${DEP_URL}"
    if command -v curl >/dev/null 2>&1; then
      curl -fL --retry 3 --retry-delay 3 -o "${DEP_SOURCE_ROOT}/${DEP_TARBALL}" "${DEP_URL}"
    else
      wget -O "${DEP_SOURCE_ROOT}/${DEP_TARBALL}" "${DEP_URL}"
    fi
    local t p
    t="$(msys_unix_path "${DEP_SOURCE_ROOT}/${DEP_TARBALL}")"
    p="$(msys_unix_path "${DEP_SOURCE_ROOT}")"
    # 兼容 .tar.xz / .tar.gz
    if ! tar -xJf "$t" -C "$p" 2>/dev/null; then
      tar -xzf "$t" -C "$p"
    fi
  fi
  echo "[${DEP_NAME}] 源码就绪: ${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}"
}

# ================= 编译参数 =================
dep_make_flags() {
  local n
  if command -v nproc >/dev/null 2>&1; then n="$(nproc)";
  else n="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"; fi
  echo "-j${n}"
}

# ================= 默认 configure 参数（静态库） =================
dep_default_configure() {
  echo "--prefix=${DEP_INSTALL}"
  if [ "${DEP_STATIC:-1}" = "1" ]; then
    echo "--enable-static --disable-shared"
  else
    echo "--disable-static --enable-shared"
  fi
  echo "--disable-programs --disable-doc --disable-debug"
}

# ================= 平台感知构建 =================
# 根据 PLATFORM 决定 target-os 与交叉编译选项（这是唯一的平台分支点）
dep_build() {
  local target_os=""
  local cross=0
  case "$PLATFORM" in
    linux)   target_os="linux" ;;
    windows) target_os="mingw32" ;;
    macos)   target_os="darwin"; cross=1 ;;
    android) target_os="android"; cross=1 ;;
    ios)     target_os="darwin"; cross=1 ;;
    *)       echo "[${DEP_NAME}] 未知平台: ${PLATFORM}"; exit 1 ;;
  esac

  export DEP_INSTALL="${DEP_STAGE_ROOT}/install-${PLATFORM}-${ARCH}"
  rm -rf "$DEP_INSTALL"
  local bd="${DEP_SOURCE_ROOT}/build-${PLATFORM}-${ARCH}"
  mkdir -p "$bd" && cd "$bd"

  local cfg=()
  cfg+=($(dep_default_configure))
  cfg+=($CONFIGURE_FLAGS)
  cfg+=(--arch="${ARCH}" --target-os="${target_os}")
  if [ "${cross}" = "1" ]; then cfg+=(--enable-cross-compile); fi
  if [ -n "${CC:-}" ]; then cfg+=(--cc="${CC}"); fi
  if [ -n "${CXX:-}" ]; then cfg+=(--cxx="${CXX}"); fi
  if [ -n "${CROSS_PREFIX:-}" ]; then cfg+=(--cross-prefix="${CROSS_PREFIX}"); fi
  if [ -n "${SYSROOT:-}" ]; then cfg+=(--sysroot="${SYSROOT}"); fi
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cfg+=(--extra-cflags="${EXTRA_CFLAGS}"); fi
  if [ -n "${EXTRA_LDFLAGS:-}" ]; then cfg+=(--extra-ldflags="${EXTRA_LDFLAGS}"); fi
  # iOS 关闭内联汇编
  if [ "$PLATFORM" = "ios" ]; then cfg+=(--disable-asm); fi

  echo "[${DEP_NAME}] configure: ${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}/configure ${cfg[*]}"
  "${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}/configure" "${cfg[@]}"
  make $(dep_make_flags)
  make install
}

# ================= 整理产物 =================
# 输出到 ${DEP_STAGE_ROOT}/${DEP_OUTPUT_DIR}/${PLAT_OUT}/${ARCH_DIR}/{include,lib}
dep_stage_output() {
  local plat_out="${DEP_PLAT_OUT:-${PLATFORM}}"
  local arch_dir="${ARCH_DIR:-${ARCH}}"
  local out="${DEP_STAGE_ROOT}/${DEP_OUTPUT_DIR}/${plat_out}/${arch_dir}"
  rm -rf "$out"; mkdir -p "$out"
  cp -a "${DEP_INSTALL}/include" "$out/include"
  cp -a "${DEP_INSTALL}/lib"     "$out/lib"
  rm -f "$out"/lib/pkgconfig/*.pc 2>/dev/null || true
  echo "[${DEP_NAME}] 已产出: ${out}"
}
