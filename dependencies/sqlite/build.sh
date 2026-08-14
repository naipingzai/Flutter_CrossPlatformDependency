#!/usr/bin/env bash
# ============================================================
# build.sh - SQLite 跨平台静态库构建（自包含）
# ============================================================
# 本脚本完全独立，不依赖仓库内任何其他脚本。
# 平台相关值（ARCH / CC / SYSROOT / EXTRA_CFLAGS 等）由
# .github/workflows/build_sqlite.yml 通过环境变量注入。
#
# SQLite 用官方 autoconf 构建，产出 libsqlite3.a。
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

# SQLite 精简配置：静态库，精简不需要的组件
DEP_CONFIGURE_FLAGS="
--enable-static
--disable-shared
--disable-dynamic-extensions
--disable-fts3
--disable-rtree"

# 源码 / 产物暂存目录
DEP_SOURCE_ROOT="${DEP_SOURCE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-src}"
DEP_STAGE_ROOT="${DEP_STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-stage}"

# ============================================================
# 【规则 B】平台规则
# ============================================================
platform_needs_cross() {
  case "$PLATFORM" in
    macos|android|ios) echo 1 ;;
    *) echo 0 ;;
  esac
}

platform_jobs() {
  if command -v nproc >/dev/null 2>&1; then echo "$(nproc)";
  else echo "$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"; fi
}

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
  echo "[${DEP_NAME}] 源码就绪: ${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}"
}

# ============================================================
# 【规则 D】构建规则 —— configure / make / install
# ============================================================
build() {
  local cross
  cross="$(platform_needs_cross)"

  local src="${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}"
  local inst="${DEP_STAGE_ROOT}/install-${PLATFORM}-${ARCH}"
  rm -rf "$inst"
  local bd="${DEP_SOURCE_ROOT}/build-${PLATFORM}-${ARCH}"
  rm -rf "$bd"; mkdir -p "$bd"

  local cfg=()
  cfg+=(--prefix="$inst")
  cfg+=($DEP_CONFIGURE_FLAGS)
  if [ -n "${CC:-}" ];        then cfg+=(--cc="${CC}"); fi
  if [ -n "${HOST:-}" ];      then cfg+=(--host="${HOST}"); fi
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cfg+=(CFLAGS="${EXTRA_CFLAGS}"); fi

  echo "[${DEP_NAME}] configure: ${cfg[*]}"
  (cd "$bd" && "$src/configure" "${cfg[@]}")
  (cd "$bd" && make -j"$(platform_jobs)" && make install)
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
  rm -f "$out"/lib/*.la "$out"/lib/pkgconfig/* 2>/dev/null || true
  echo "[${DEP_NAME}] 已产出: ${out}"
}

# ============================================================
# 执行
# ============================================================
fetch_source
build
stage_output
echo "[${DEP_NAME}] ${PLATFORM}/${ARCH:-?} 构建完成"
