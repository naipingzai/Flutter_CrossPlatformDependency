#!/usr/bin/env bash
# ============================================================
# build.sh - stb_image 跨平台静态库构建（自包含）
# ============================================================
# 本脚本完全独立，不依赖仓库内任何其他脚本。
# 平台相关值（ARCH / CC / AR / EXTRA_CFLAGS 等）由
# .github/workflows/build_stb_image.yml 通过环境变量注入。
#
# stb_image 为单头文件库：把 STB_IMAGE_IMPLEMENTATION 放进独立
# 编译单元，产出 libstb_image.a（消费方只包含声明并链接该库）。
#
# 用法：bash dependencies/stb_image/build.sh
# ============================================================
set -euo pipefail

# ============================================================
# 【规则 A】依赖常量
# ============================================================
DEP_NAME="stb_image"
DEP_VERSION="2c980bb"                       # 固定 stb 提交（无版本号）
DEP_TARBALL="stb-${DEP_VERSION}.tar.gz"
DEP_URL="https://github.com/nothings/stb/archive/refs/heads/master.tar.gz"
DEP_SRC_DIR="stb-master"

# 源码 / 产物暂存目录
DEP_SOURCE_ROOT="${DEP_SOURCE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-src}"
DEP_STAGE_ROOT="${DEP_STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-stage}"

# ============================================================
# 【规则 B】平台规则 —— 简单 C 库，仅需 CC/AR
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
  # 校验 stb_image.h 存在
  test -f "${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}/stb_image.h"
  echo "[${DEP_NAME}] 源码就绪: ${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}"
}

# ============================================================
# 【规则 D】构建规则 —— 编译为 libstb_image.a
# ============================================================
build() {
  local cc ar
  cc="$(platform_cc)"; ar="$(platform_ar)"

  local src="${DEP_SOURCE_ROOT}/${DEP_SRC_DIR}"
  local inst="${DEP_STAGE_ROOT}/install-${PLATFORM}-${ARCH}"
  rm -rf "$inst"; mkdir -p "$inst/include" "$inst/lib"
  local bd="${DEP_SOURCE_ROOT}/build-${PLATFORM}-${ARCH}"
  rm -rf "$bd"; mkdir -p "$bd"

  # 生成独立编译单元（定义 STB_IMAGE_IMPLEMENTATION）
  printf '#define STB_IMAGE_IMPLEMENTATION\n#include "stb_image.h"\n' > "${bd}/stb_image.c"

  # 组装编译器参数（含可选的交叉编译 isysroot）
  local cflags=(-O2 -fPIC -I"${src}")
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cflags+=($EXTRA_CFLAGS); fi
  if [ -n "${SYSROOT:-}" ]; then cflags+=("-isysroot" "${SYSROOT}"); fi

  echo "[${DEP_NAME}] 编译 stb_image.c"
  # shellcheck disable=SC2086
  "${cc}" "${cflags[@]}" -c "${bd}/stb_image.c" -o "${bd}/stb_image.o"

  echo "[${DEP_NAME}] 归档 libstb_image.a"
  # shellcheck disable=SC2086
  ${ar} rcs "${inst}/lib/libstb_image.a" "${bd}/stb_image.o"

  # 复制头文件
  cp "${src}/stb_image.h" "${inst}/include/stb_image.h"
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
