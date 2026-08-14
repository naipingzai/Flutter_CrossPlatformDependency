#!/usr/bin/env bash
# ============================================================
# build.sh - SQLite 跨平台静态库构建（自包含）
# ============================================================
# 本脚本完全独立，不依赖仓库内任何其他脚本。
# 平台相关值（ARCH / CC / AR / EXTRA_CFLAGS / SYSROOT 等）由
# .github/workflows/build_sqlite.yml 通过环境变量注入。
#
# 直接用 CC 编译 SQLite amalgamation（sqlite3.c），避免 autoconf
# 交叉编译问题，与 miniz/stb_image 一致，产出 libsqlite3.a。
#
# 用法：bash dependencies/sqlite/build.sh
# ============================================================
set -euo pipefail

# ============================================================
# 【规则 A】依赖常量
# ============================================================
DEP_NAME="sqlite"
DEP_VERSION="3460100"
DEP_TARBALL="sqlite-autoconf-${DEP_VERSION}.tar.gz"
DEP_URL="https://www.sqlite.org/2024/${DEP_TARBALL}"
DEP_SRC_DIR="sqlite-autoconf-${DEP_VERSION}"

# 源码 / 产物暂存目录
DEP_SOURCE_ROOT="${DEP_SOURCE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-src}"
DEP_STAGE_ROOT="${DEP_STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-stage}"

# ============================================================
# 【规则 B】平台规则 —— 仅需 CC/AR
# ============================================================
platform_cc()  { echo "${CC:-cc}"; }
platform_ar()  { echo "${AR:-ar}"; }

# ============================================================
# 【规则 C】下载规则
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
  local t p
  if command -v cygpath >/dev/null 2>&1; then
    t="$(cygpath -u "${DEP_SOURCE_ROOT}/${DEP_TARBALL}")"
    p="$(cygpath -u "${DEP_SOURCE_ROOT}")"
  else
    t="${DEP_SOURCE_ROOT}/${DEP_TARBALL}"; p="${DEP_SOURCE_ROOT}"
  fi
  tar -xzf "$t" -C "$p"
  # amalgamation 需含 sqlite3.c / sqlite3.h
  test -f "${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}/sqlite3.c"
  echo "[${DEP_NAME}] 源码就绪: ${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}"
}

# ============================================================
# 【规则 D】构建规则 —— 直接编译 amalgamation
# ============================================================
build() {
  local cc ar
  cc="$(platform_cc)"; ar="$(platform_ar)"

  local src="${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}"
  local inst="${DEP_STAGE_ROOT}/install-${PLATFORM}-${ARCH}"
  rm -rf "$inst"; mkdir -p "$inst/include" "$inst/lib"
  local bd="${DEP_SOURCE_ROOT}/build-${PLATFORM}-${ARCH}"
  rm -rf "$bd"; mkdir -p "$bd"

  local cflags=(-O2 -fPIC)
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cflags+=($EXTRA_CFLAGS); fi
  if [ -n "${SYSROOT:-}" ]; then cflags+=("-isysroot" "${SYSROOT}"); fi

  echo "[${DEP_NAME}] 编译 sqlite3.c"
  "${cc}" "${cflags[@]}" -c "${src}/sqlite3.c" -o "${bd}/sqlite3.o"

  echo "[${DEP_NAME}] 归档 libsqlite3.a"
  "${ar}" rcs "${inst}/lib/libsqlite3.a" "${bd}/sqlite3.o"

  # 复制头文件
  cp "${src}/sqlite3.h"     "${inst}/include/sqlite3.h"
  cp "${src}/sqlite3ext.h"  "${inst}/include/sqlite3ext.h"
}

# ============================================================
# 【规则 E】产物整理规则
# ============================================================
stage_output() {
  local plat_out="${DEP_PLAT_OUT:-${PLATFORM}}"
  local arch_dir="${ARCH_DIR:-${ARCH}}"
  local out="${DEP_STAGE_ROOT}/${DEP_NAME}/${plat_out}/${arch_dir}"
  rm -rf "$out"; mkdir -p "$out"
  cp -a "${DEP_STAGE_ROOT}/install-${PLATFORM}-${ARCH}/include" "$out/include"
  cp -a "${DEP_STAGE_ROOT}/install-${PLATFORM}-${ARCH}/lib"     "$out/lib"
  echo "[${DEP_NAME}] 已产出: ${out}"
}

# ============================================================
# 执行
# ============================================================
fetch_source
build
stage_output
echo "[${DEP_NAME}] ${PLATFORM}/${ARCH:-?} 构建完成"
