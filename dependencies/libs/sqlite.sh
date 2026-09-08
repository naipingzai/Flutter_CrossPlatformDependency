#!/usr/bin/env bash
# ============================================================
# libs/sqlite.sh —— SQLite 编译（amalgamation 直接编译）
# ============================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common/functions.sh"

build_sqlite() {
  local DEP_SRC_DIR="sqlite-autoconf-${SQLITE_VERSION}"
  dl_extract sqlite "https://www.sqlite.org/2024/sqlite-autoconf-${SQLITE_VERSION}.tar.gz" "$DEP_SRC_DIR" "sqlite.tar.gz"

  local cc ar
  cc="$(platform_cc)"; ar="$(platform_ar)"
  local src="${SRC_ROOT}/sqlite/${DEP_SRC_DIR}"

  local inst="${STAGE_ROOT}/sqlite-inst"
  rm -rf "$inst"; mkdir -p "$inst/include" "$inst/lib"

  local bd="${SRC_ROOT}/sqlite/build"
  rm -rf "$bd"; mkdir -p "$bd"

  local cflags=(-O2 -fPIC)
  if [ -n "${EXTRA_CFLAGS:-}" ]; then cflags+=($EXTRA_CFLAGS); fi

  if [ -n "${SYSROOT:-}" ]; then
    "${cc}" "${cflags[@]}" "-isysroot" "${SYSROOT}" -c "${src}/sqlite3.c" -o "$bd/sqlite3.o"
  else
    "${cc}" "${cflags[@]}" -c "${src}/sqlite3.c" -o "$bd/sqlite3.o"
  fi

  ${ar} rcs "$inst/lib/libsqlite3.a" "$bd/sqlite3.o"
  create_shared_lib "${cc}" "$inst/lib/libsqlite3.$(shared_ext)" "$bd/sqlite3.o"
  cp "${src}/sqlite3.h" "$inst/include/sqlite3.h"
  cp "${src}/sqlite3ext.h" "$inst/include/sqlite3ext.h"

  stage_lib sqlite
  cp -a "$inst/include" "${STAGE_ROOT}/sqlite/${PLATFORM}/${ARCH_DIR}/include"
  cp -a "$inst/lib" "${STAGE_ROOT}/sqlite/${PLATFORM}/${ARCH_DIR}/lib"

  # Android PIC 校验
  if [ "$PLATFORM" = "android" ]; then
    android_check_pic "$inst/lib/libsqlite3.a"
  fi

  echo "[sqlite] 完成（静态库 + 动态库）"
}

build_sqlite
