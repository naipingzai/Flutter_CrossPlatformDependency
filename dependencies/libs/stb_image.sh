#!/usr/bin/env bash
# ============================================================
# libs/stb_image.sh —— stb_image 编译（直接编译）
# ============================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common/functions.sh"

build_stb_image() {
  local DEP_SRC_DIR="stb-master"
  dl_extract stb_image "https://github.com/nothings/stb/archive/refs/heads/master.tar.gz" "$DEP_SRC_DIR" "stb.tar.gz"

  local cc ar
  cc="$(platform_cc)"; ar="$(platform_ar)"
  local src="${SRC_ROOT}/stb_image/${DEP_SRC_DIR}"

  local inst="${STAGE_ROOT}/stb_image-inst"
  rm -rf "$inst"; mkdir -p "$inst/include" "$inst/lib"

  local bd="${SRC_ROOT}/stb_image/build"
  rm -rf "$bd"; mkdir -p "$bd"

  printf '#define STB_IMAGE_IMPLEMENTATION\n#include "stb_image.h"\n' > "${bd}/stb_image.c"

  local cflags=(-O2 -fPIC -I"${src}")
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cflags+=($EXTRA_CFLAGS); fi

  if [ -n "${SYSROOT:-}" ]; then
    "${cc}" "${cflags[@]}" "-isysroot" "${SYSROOT}" -c "${bd}/stb_image.c" -o "${bd}/stb_image.o"
  else
    "${cc}" "${cflags[@]}" -c "${bd}/stb_image.c" -o "${bd}/stb_image.o"
  fi

  ${ar} rcs "$inst/lib/libstb_image.a" "$bd/stb_image.o"
  create_shared_lib "${cc}" "$inst/lib/libstb_image.$(shared_ext)" "$bd/stb_image.o"
  cp "${src}/stb_image.h" "$inst/include/stb_image.h"

  stage_lib stb_image
  cp -a "$inst/include" "${STAGE_ROOT}/stb_image/${PLATFORM}/${ARCH_DIR}/include"
  cp -a "$inst/lib" "${STAGE_ROOT}/stb_image/${PLATFORM}/${ARCH_DIR}/lib"

  # Android PIC 校验
  if [ "$PLATFORM" = "android" ]; then
    android_check_pic "$inst/lib/libstb_image.a"
  fi

  echo "[stb_image] 完成（静态库 + 动态库）"
}

build_stb_image
