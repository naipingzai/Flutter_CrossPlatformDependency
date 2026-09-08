#!/usr/bin/env bash
# ============================================================
# libs/miniz.sh —— miniz 编译（直接编译）
# ============================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common/functions.sh"

build_miniz() {
  local DEP_SRC_DIR="miniz-${MINIZ_VERSION}"
  dl_extract miniz "https://github.com/richgel999/miniz/archive/refs/tags/${MINIZ_VERSION}.tar.gz" "$DEP_SRC_DIR" "miniz.tar.gz"

  local cc ar
  cc="$(platform_cc)"; ar="$(platform_ar)"
  local src="${SRC_ROOT}/miniz/${DEP_SRC_DIR}"

  # 生成 miniz_export.h（如果不存在）
  if [ ! -f "${src}/miniz_export.h" ]; then
    printf '#pragma once\n#define MINIZ_EXPORT\n' > "${src}/miniz_export.h"
  fi

  local inst="${STAGE_ROOT}/miniz-inst"
  rm -rf "$inst"; mkdir -p "$inst/include" "$inst/lib"

  local bd="${SRC_ROOT}/miniz/build"
  rm -rf "$bd"; mkdir -p "$bd"

  local cflags=(-O2 -fPIC -I"${src}")
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cflags+=($EXTRA_CFLAGS); fi

  local objs=()
  for s in $MINIZ_SOURCES; do
    local o="${bd}/${s%.c}.o"
    if [ -n "${SYSROOT:-}" ]; then
      "${cc}" "${cflags[@]}" "-isysroot" "${SYSROOT}" -c "${src}/${s}" -o "$o"
    else
      "${cc}" "${cflags[@]}" -c "${src}/${s}" -o "$o"
    fi
    objs+=("$o")
  done

  ${ar} rcs "$inst/lib/libminiz.a" "${objs[@]}"
  create_shared_lib "${cc}" "$inst/lib/libminiz.$(shared_ext)" "${objs[@]}"

  for h in $MINIZ_HEADERS; do
    cp "${src}/${h}" "$inst/include/${h}"
  done

  stage_lib miniz
  cp -a "$inst/include" "${STAGE_ROOT}/miniz/${PLATFORM}/${ARCH_DIR}/include"
  cp -a "$inst/lib" "${STAGE_ROOT}/miniz/${PLATFORM}/${ARCH_DIR}/lib"

  # Android PIC 校验
  if [ "$PLATFORM" = "android" ]; then
    android_check_pic "$inst/lib/libminiz.a"
  fi

  echo "[miniz] 完成（静态库 + 动态库）"
}

build_miniz
