#!/usr/bin/env bash
# ============================================================
# build_ios.sh - CPython for iOS（自包含）
# ============================================================
# 上游 CPython autoconf 不支持 iOS 交叉编译，改用官方认可的
# pybee/Python-Apple-support 构建 iOS 嵌入用 Python。
#
# 流程：clone Python-Apple-support(3.12 分支) → make iOS →
#       产物 tarball(含 Python.xcframework) → 整理到统一结构。
#
# 产物：
#   python/ios/arm64/
#   ├── include/            头文件
#   ├── lib/                标准库 python3.x/（该 slice 可作 PYTHONHOME）
#   └── Python.xcframework/ 运行时库（APP 用于链接）
#
# 用法：bash dependencies/python/build_ios.sh
# ============================================================
set -euo pipefail

# ============================================================
# 【规则 A】依赖常量
# ============================================================
DEP_NAME="python"
DEP_VERSION="3.12.7"
PAS_REPO="https://github.com/beeware/Python-Apple-support.git"
PAS_BRANCH="3.12"     # 对应 Python 3.12

DEP_SOURCE_ROOT="${DEP_SOURCE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-ios-src}"
DEP_STAGE_ROOT="${DEP_STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-stage}"

# ============================================================
# 【规则 B】准备：clone Python-Apple-support 与构建工具
# ============================================================
prepare() {
  mkdir -p "$DEP_SOURCE_ROOT"
  cd "$DEP_SOURCE_ROOT"
  if [ ! -d "Python-Apple-support" ]; then
    echo "[${DEP_NAME}] clone Python-Apple-support (${PAS_BRANCH})"
    git clone --depth 1 -b "$PAS_BRANCH" "$PAS_REPO" Python-Apple-support
  fi
  cd Python-Apple-support
  # 构建工具依赖
  python3 -m pip install --upgrade setuptools wheel 2>/dev/null || true
}

# ============================================================
# 【规则 C】构建
# ============================================================
build() {
  echo "[${DEP_NAME}] ==== make iOS（arm64 真机 + 模拟器，耗时较长）===="
  make iOS
}

# ============================================================
# 【规则 D】产物整理
# ============================================================
stage_output() {
  local pas="$DEP_SOURCE_ROOT/Python-Apple-support"
  local tarball
  tarball="$(ls -1 "$pas"/dist/*.tar.gz 2>/dev/null | head -1)"
  if [ -z "$tarball" ]; then
    echo "[${DEP_NAME}] 错误：未在 dist/ 找到产物包" >&2
    ls -la "$pas"/dist 2>/dev/null || true
    exit 1
  fi
  echo "[${DEP_NAME}] 产物包: $tarball"

  local extract="$DEP_SOURCE_ROOT/extract-ios"
  rm -rf "$extract"; mkdir -p "$extract"
  tar -xzf "$tarball" -C "$extract"

  local xcframe
  xcframe="$(find "$extract" -type d -name 'Python.xcframework' | head -1)"
  if [ -z "$xcframe" ]; then
    echo "[${DEP_NAME}] 错误：未找到 Python.xcframework" >&2
    find "$extract" -maxdepth 4 -type d
    exit 1
  fi
  echo "[${DEP_NAME}] xcframework: $xcframe"

  local slice="$xcframe/ios-arm64"
  if [ ! -d "$slice" ]; then
    echo "[${DEP_NAME}] 错误：未找到真机 ios-arm64 slice" >&2
    ls -1 "$xcframe"
    exit 1
  fi

  local out="$DEP_STAGE_ROOT/$DEP_NAME/ios/arm64"
  rm -rf "$out"; mkdir -p "$out"
  cp -a "$xcframe" "$out/Python.xcframework"
  if [ -d "$slice/include" ]; then cp -a "$slice/include" "$out/include"; fi
  if [ -d "$slice/lib" ];     then cp -a "$slice/lib"     "$out/lib"; fi
  echo "[${DEP_NAME}] iOS 已产出: ${out}"
  ls -la "$out"
}

# ============================================================
# 执行
# ============================================================
prepare
build
stage_output
echo "[${DEP_NAME}] iOS 构建完成"
