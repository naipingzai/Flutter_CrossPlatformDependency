#!/usr/bin/env bash
# ============================================================
# build.sh - miniz 跨平台静态库构建（自包含）
# ============================================================
# 本脚本完全独立，不依赖仓库内任何其他脚本。
# 平台相关值（ARCH / CC / AR / EXTRA_CFLAGS 等）由
# .github/workflows/build_miniz.yml 通过环境变量注入。
#
# miniz 2.x 拆分为多 TU（miniz.c/miniz_zip.c/miniz_tdef.c/miniz_tinfl.c），
# 直接编译为 libminiz.a（无 autoconf）。
#
# 用法：bash dependencies/miniz/build.sh
# ============================================================
set -euo pipefail

# ============================================================
# 【规则 A】依赖常量
# ============================================================
DEP_NAME="miniz"
DEP_VERSION="2.2.0"
DEP_TARBALL="miniz-${DEP_VERSION}.tar.gz"
DEP_URL="https://github.com/richgel999/miniz/archive/refs/tags/${DEP_VERSION}.tar.gz"
DEP_SRC_DIR="miniz-${DEP_VERSION}"

# 源码 / 产物暂存目录
DEP_SOURCE_ROOT="${DEP_SOURCE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-src}"
DEP_STAGE_ROOT="${DEP_STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-stage}"

# 需要编入的源文件
DEP_SOURCES="miniz.c miniz_zip.c miniz_tdef.c miniz_tinfl.c"
# 需要随库发布的头文件
DEP_HEADERS="miniz.h miniz_common.h miniz_export.h miniz_tdef.h miniz_tinfl.h miniz_zip.h"

# ============================================================
# 【规则 B】平台规则 —— 简单 C 库，仅需 CC/AR
# ============================================================
platform_cc()  { echo "${CC:-cc}"; }
platform_ar()  { echo "${AR:-ar}"; }

# 并行编译进程数
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
# 【规则 D】构建规则 —— 直接编译为静态库
# ============================================================
build() {
  local cc ar jobs
  cc="$(platform_cc)"; ar="$(platform_ar)"; jobs="$(platform_jobs)"

  local src="${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}"

  # miniz_export.h 由上游 amalgamate 生成，源码包不含；静态库无需导出，缺失时生成 stub
  if [ ! -f "${src}/miniz_export.h" ]; then
    echo "[${DEP_NAME}] 生成 miniz_export.h stub（静态库无需符号导出）"
    printf '#pragma once\n#define MINIZ_EXPORT\n' > "${src}/miniz_export.h"
  fi

  local inst="${DEP_STAGE_ROOT}/install-${PLATFORM}-${ARCH}"
  rm -rf "$inst"; mkdir -p "$inst/include" "$inst/lib"
  local bd="${DEP_SOURCE_ROOT}/build-${PLATFORM}-${ARCH}"
  rm -rf "$bd"; mkdir -p "$bd"

  local objs=()
  # 组装编译器参数（含可选的交叉编译 isysroot）
  local cflags=(-O2 -fPIC -I"${src}")
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cflags+=($EXTRA_CFLAGS); fi
  if [ -n "${SYSROOT:-}" ]; then cflags+=("-isysroot" "${SYSROOT}"); fi
  for s in $DEP_SOURCES; do
    local o="${bd}/${s%.c}.o"
    echo "[${DEP_NAME}] 编译 ${s} -> ${o}"
    # shellcheck disable=SC2086
    "${cc}" "${cflags[@]}" -c "${src}/${s}" -o "${o}"
    objs+=("$o")
  done

  echo "[${DEP_NAME}] 归档 libminiz.a"
  # shellcheck disable=SC2086
  ${ar} rcs "${inst}/lib/libminiz.a" "${objs[@]}"

  # 复制头文件
  for h in $DEP_HEADERS; do
    cp "${src}/${h}" "${inst}/include/${h}"
  done
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
