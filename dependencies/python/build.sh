#!/usr/bin/env bash
# ============================================================
# build.sh - CPython 嵌入用静态库构建（自包含）
# ============================================================
# 产出可被 APP 直接链接的嵌入式 Python 环境：
#   - libpython3.x.a        静态解释器库
#   - python3.x/            标准库（stdlib）
#   - python3.x/            头文件（Python.h 等）
#
# 平台相关值（PLATFORM / ARCH / HOST_TRIPLE / BUILD_PYTHON / CC 等）
# 由 .github/workflows/build_python.yml 通过环境变量注入。
#
# 用法：bash dependencies/python/build.sh
# ============================================================
set -euo pipefail

# ============================================================
# 【规则 A】依赖常量 —— 新增/升级版本时修改本段
# ============================================================
DEP_NAME="python"
DEP_VERSION="3.12.7"
DEP_TARBALL="Python-${DEP_VERSION}.tgz"
DEP_URL="https://www.python.org/ftp/python/${DEP_VERSION}/${DEP_TARBALL}"
DEP_SRC_DIR="Python-${DEP_VERSION}"

# 源码 / 产物暂存目录
DEP_SOURCE_ROOT="${DEP_SOURCE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-src}"
DEP_STAGE_ROOT="${DEP_STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-stage}"

# ============================================================
# 【规则 B】平台规则 —— 构建机 / 目标机三元组
# ============================================================
# 构建机三元组（native 构建时即目标机）
build_triple() {
  if [ -n "${BUILD_TRIPLE:-}" ]; then echo "$BUILD_TRIPLE"; return; fi
  local m
  m="$(uname -m)"
  case "$(uname -s)" in
    Linux)  case "$m" in x86_64) echo x86_64-linux-gnu;; aarch64) echo aarch64-linux-gnu;; esac ;;
    Darwin) case "$m" in x86_64) echo x86_64-apple-darwin;; arm64) echo arm64-apple-darwin;; esac ;;
    *)      echo "$m-pc-linux-gnu" ;;
  esac
}

# 目标机三元组（交叉编译时由 workflow 传 HOST_TRIPLE；否则 = 构建机）
target_triple() {
  if [ -n "${HOST_TRIPLE:-}" ]; then echo "$HOST_TRIPLE"; else build_triple; fi
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
# CPython 特点：默认即静态 libpython.a；用 --host/--build 交叉编译；
# 交叉编译需提供与目标同版本的主机 python（--with-build-python）。
build() {
  local inst="${DEP_STAGE_ROOT}/install-${PLATFORM}-${ARCH}"
  rm -rf "$inst"
  local bd="${DEP_SOURCE_ROOT}/build-${PLATFORM}-${ARCH}"
  mkdir -p "$bd" && cd "$bd"

  local cfg=()
  cfg+=(--prefix="$inst")
  cfg+=(--without-ensurepip)      # 不要 pip，减小体积
  cfg+=(--disable-shared)         # 只出静态库
  cfg+=(--without-doc-strings)    # 减小体积

  # 交叉编译（Android / iOS / MinGW-Windows）
  if [ -n "${HOST_TRIPLE:-}" ]; then
    cfg+=(--host="${HOST_TRIPLE}" --build="$(build_triple)")
    if [ -n "${BUILD_PYTHON:-}" ]; then
      cfg+=(--with-build-python="${BUILD_PYTHON}")
    else
      echo "[${DEP_NAME}] 交叉编译需要 BUILD_PYTHON（与目标同版本的主机 python）" >&2
      exit 1
    fi
  fi

  # 交叉工具链环境变量（由 workflow 注入）
  [ -n "${CC:-}" ]        && export CC
  [ -n "${CXX:-}" ]       && export CXX
  [ -n "${AR:-}" ]        && export AR
  [ -n "${RANLIB:-}" ]    && export RANLIB
  [ -n "${STRIP:-}" ]     && export STRIP
  [ -n "${SYSROOT:-}" ]   && export CFLAGS="${CFLAGS:-} --sysroot=${SYSROOT}"
  [ -n "${EXTRA_CFLAGS:-}" ] && export CFLAGS="${CFLAGS:-} ${EXTRA_CFLAGS}"
  [ -n "${EXTRA_LDFLAGS:-}" ] && export LDFLAGS="${LDFLAGS:-} ${EXTRA_LDFLAGS}"

  echo "[${DEP_NAME}] configure: ${cfg[*]}"
  "${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}/configure" "${cfg[@]}"
  make -j"$(build_jobs)"
  make install
}

build_jobs() {
  if command -v nproc >/dev/null 2>&1; then echo "$(nproc)";
  else echo "$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"; fi
}

# ============================================================
# 【规则 E】产物整理 —— 输出到统一结构
#   ${DEP_STAGE_ROOT}/python/<PLAT>/<ARCH>/{include,lib}
#   lib/ 内含 libpython3.x.a 与 python3.x/（标准库）
# ============================================================
stage_output() {
  local plat_out="${DEP_PLAT_OUT:-${PLATFORM}}"
  local arch_dir="${ARCH_DIR:-${ARCH}}"
  local inst="${DEP_STAGE_ROOT}/install-${PLATFORM}-${ARCH}"
  local out="${DEP_STAGE_ROOT}/${DEP_NAME}/${plat_out}/${arch_dir}"
  rm -rf "$out"; mkdir -p "$out"
  cp -a "${inst}/include" "$out/include"
  cp -a "${inst}/lib"     "$out/lib"
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
