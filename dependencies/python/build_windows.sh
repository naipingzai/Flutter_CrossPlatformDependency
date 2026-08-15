#!/usr/bin/env bash
# ============================================================
# build_windows.sh - CPython for Windows（自包含）
# ============================================================
# 说明：CPython 在 Windows 官方用 MSVC/PCbuild 构建，autoconf/MinGW
# 不兼容。改用官方「Windows embeddable 包」+ 源码头文件 + 生成导入库，
# 得到可被 APP 直接链接内嵌的 Windows Python。
#
# 产物（统一结构 python/windows/x86_64/{include,lib}）：
#   include/python3.12/  头文件（Python.h + pyconfig.h）
#   lib/
#     python312.dll      运行时（APP 打包随程序分发）
#     libpython312.a     MinGW 导入库（链接用 -lpython312）
#     python312.zip      标准库（压缩，随运行时分发）
#     *.pyd              C 扩展模块
#
# 用法：bash dependencies/python/build_windows.sh
# ============================================================
set -euo pipefail

# ============================================================
# 【规则 A】依赖常量
# ============================================================
DEP_NAME="python"
DEP_VERSION="3.12.7"
EMBED_URL="https://www.python.org/ftp/python/${DEP_VERSION}/python-${DEP_VERSION}-embed-amd64.zip"
SRC_URL="https://www.python.org/ftp/python/${DEP_VERSION}/Python-${DEP_VERSION}.tgz"

SRC_ROOT="${SRC_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-windows-src}"
STAGE_ROOT="${STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-stage}"

# ============================================================
# 【规则 B】准备：下载 embeddable 包与源码（取头文件）
# ============================================================
prepare() {
  mkdir -p "$SRC_ROOT"
  cd "$SRC_ROOT"

  if [ ! -d "embed" ]; then
    echo "[${DEP_NAME}] 下载 embeddable 包"
    curl -fL --retry 5 --retry-all-errors --connect-timeout 20 -o python-embed.zip "$EMBED_URL"
    mkdir -p embed && cd embed
    unzip -q ../python-embed.zip
    cd ..
  fi

  if [ ! -d "Python-${DEP_VERSION}" ]; then
    echo "[${DEP_NAME}] 下载源码（取头文件）"
    curl -fL --retry 5 --retry-all-errors --connect-timeout 20 -o Python.tgz "$SRC_URL"
    tar -xzf Python.tgz
  fi
}

# ============================================================
# 【规则 C】整理产物
# ============================================================
stage_output() {
  local out="$STAGE_ROOT/$DEP_NAME/windows/x86_64"
  rm -rf "$out"; mkdir -p "$out"

  # --- include：源码头文件 + Windows pyconfig.h ---
  mkdir -p "$out/include/python3.12"
  cp -a "$SRC_ROOT/Python-${DEP_VERSION}/Include/." "$out/include/python3.12/"
  cp "$SRC_ROOT/Python-${DEP_VERSION}/PC/pyconfig.h" "$out/include/python3.12/"

  # --- lib：DLL + 标准库 zip + .pyd 扩展 ---
  mkdir -p "$out/lib"
  cp "$SRC_ROOT/embed/"*.dll "$out/lib/" 2>/dev/null || true
  cp "$SRC_ROOT/embed/python${DEP_VERSION%.*}.zip" "$out/lib/" 2>/dev/null || true
  cp "$SRC_ROOT/embed/"*.pyd "$out/lib/" 2>/dev/null || true

  # --- 生成 MinGW 导入库 libpython312.a（链接用 -lpython312） ---
  local dll
  dll="$(ls "$out"/lib/python3*.dll 2>/dev/null | head -1)"
  if [ -n "$dll" ] && command -v gendef >/dev/null 2>&1 && command -v dlltool >/dev/null 2>&1; then
    echo "[${DEP_NAME}] 生成导入库"
    ( cd "$out/lib" && gendef "$(basename "$dll")" && dlltool -d python312.def -l libpython312.a -D "$(basename "$dll")" )
    rm -f "$out/lib/python312.def"
  else
    echo "[${DEP_NAME}] 警告：未生成导入库（无 gendef/dlltool），APP 需自行链接 DLL"
  fi

  echo "[${DEP_NAME}] Windows 已产出: ${out}"
  ls -la "$out" "$out/lib" 2>/dev/null
}

# ============================================================
# 执行
# ============================================================
prepare
stage_output
echo "[${DEP_NAME}] Windows 构建完成"
