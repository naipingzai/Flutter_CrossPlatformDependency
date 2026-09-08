#!/usr/bin/env bash
# ============================================================
# libs/python.sh —— Python 编译
# 平台策略：
#   linux/macos: 源码 autoconf 编译
#   windows: 预编译 embed zip
#   android: Python-Apple-support 风格的交叉编译 + config.site
#   ios: Python-Apple-support xcframework
# ============================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common/functions.sh"

build_python() {
  case "$PLATFORM" in
  linux|macos) build_python_autoconf ;;
  windows)     build_python_windows ;;
  android)     build_python_android ;;
  ios)         build_python_ios ;;
  esac
}

# ---- Linux / macOS: autoconf 源码编译 ----
build_python_autoconf() {
  local inst="${STAGE_ROOT}/python-inst"
  rm -rf "$inst"

  dl_extract python "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz" "Python-${PYTHON_VERSION}" "python.tar.xz"
  cd "${SRC_ROOT}/python/Python-${PYTHON_VERSION}"

  local cfg=()
  if [ "$PLATFORM" = "macos" ]; then
    # macOS 需要 unset 交叉编译变量，使用本机编译器
    (
      unset CC CXX CROSS_COMPILE
      if [ "$(uname -m)" = "arm64" ]; then
        ./configure "--prefix=$inst" ac_cv_buggy_getaddrinfo=no "$@"
      else
        ./configure "--prefix=$inst" ac_cv_buggy_getaddrinfo=no "$@"
      fi
      make -j"$(platform_jobs)"
      make install
    )
  else
    # Linux 原生编译
    ./configure "--prefix=$inst" ac_cv_buggy_getaddrinfo=no "$@"
    make -j"$(platform_jobs)"
    make install
  fi

  local out="${STAGE_ROOT}/python/${PLATFORM}/${ARCH_DIR}"
  rm -rf "$out"; mkdir -p "$out"
  cp -a "$inst/include" "$out/include"
  cp -a "$inst/lib" "$out/lib"

  if [ ! -f "$out/include/python3.12/Python.h" ] && [ ! -f "$out/include/Python.h" ]; then
    echo "[python] 错误：未生成 Python.h" >&2; exit 1
  fi

  echo "[python] 完成（静态库 + 动态库）"
}

# ---- Windows: 预编译 embed zip ----
build_python_windows() {
  local inst="${STAGE_ROOT}/python-inst"
  rm -rf "$inst"; mkdir -p "$inst"

  # 下载预编译 embeddable package
  curl -fL --retry 5 --retry-all-errors \
    -o "${SRC_ROOT}/python-embed.zip" \
    "https://www.python.org/ftp/python/${PYTHON_VERSION}/python-${PYTHON_VERSION}-embed-amd64.zip"

  rm -rf "${SRC_ROOT}/python-embed"
  mkdir -p "${SRC_ROOT}/python-embed"

  if command -v unzip >/dev/null 2>&1; then
    unzip -o "${SRC_ROOT}/python-embed.zip" -d "${SRC_ROOT}/python-embed"
  else
    7z x "${SRC_ROOT}/python-embed.zip" -o"${SRC_ROOT}/python-embed"
  fi

  cp -a "${SRC_ROOT}/python-embed/." "$inst/"

  # 将 lib 目录映射为动态库目录
  local out="${STAGE_ROOT}/python/${PLATFORM}/${ARCH_DIR}"
  rm -rf "$out"; mkdir -p "$out"
  cp -a "$inst"/* "$out/" 2>/dev/null || true

  if [ ! -f "$out/python${PYTHON_VERSION%.?}-3.dll" ] && [ ! -f "$out/python3.dll" ]; then
    echo "[python] 警告：未找到 python DLL" >&2
  fi

  echo "[python] 完成（Windows 预编译 embed 包）"
}

# ---- Android: 交叉编译 + config.site ----
build_python_android() {
  local inst="${STAGE_ROOT}/python-inst"
  rm -rf "$inst"; mkdir -p "$inst"

  dl_extract python "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz" "Python-${PYTHON_VERSION}" "python.tar.xz"
  local src="${SRC_ROOT}/python/Python-${PYTHON_VERSION}"

  # 必须设置 HOST_TRIPLE 和 BUILD_PYTHON
  HOST_TRIPLE="${HOST_TRIPLE:-aarch64-linux-android}"
  BUILD_TRIPLE="${BUILD_TRIPLE:-x86_64-linux-gnu}"
  BUILD_PYTHON="${BUILD_PYTHON:-python3}"

  local ndk_sysroot="${SYSROOT:-}"
  local api="${API_LEVEL:-21}"

  # 生成 config.site
  cat > "${src}/Modules/config.site" <<'CONFIGEOF'
SOABI=$(ILP)
CONFIGEOF

  local cfg=(
    "--host=${HOST_TRIPLE}"
    "--build=${BUILD_TRIPLE}"
    "--with-build-python=${BUILD_PYTHON}"
    "--enable-shared"
    "--disable-ipv6"
    "ac_cv_buggy_getaddrinfo=no"
    "ac_cv_file__dev_ptmx=yes"
    "ac_cv_file__dev_ptc=no"
    "Py_ENABLE_SHARED=1"
  )

  export CONFIG_SITE="${src}/Modules/config.site"
  export CFLAGS="${EXTRA_CFLAGS:-} -I${ndk_sysroot}/usr/include"
  export LDFLAGS="${EXTRA_LDFLAGS:-}"
  export HOSTCC="gcc"
  export BUILD_CC="gcc"

  # 使用 NDK clang 编译
  export CC="${CC}"
  export CXX="${CXX:-}"

  cd "$src"
  ./configure "--prefix=$inst" "${cfg[@]}"
  make -j"$(platform_jobs)"
  make install

  local out="${STAGE_ROOT}/python/${PLATFORM}/${ARCH_DIR}"
  rm -rf "$out"; mkdir -p "$out"
  cp -a "$inst/include" "$out/include" 2>/dev/null || true
  cp -a "$inst/lib" "$out/lib" 2>/dev/null || true

  unset CONFIG_SITE HOSTCC BUILD_CC

  if [ ! -f "$out/include/python3.12/Python.h" ] && [ ! -f "$out/include/Python.h" ]; then
    echo "[python] 错误：未生成 Python.h" >&2; exit 1
  fi

  echo "[python] 完成（Android 交叉编译）"
}

# ---- iOS: Python-Apple-support xcframework ----
build_python_ios() {
  local xcframe_url="https://github.com/pybee/Python-Apple-support/releases/download/3.12-b9/Python-3.12-iOS-support.b9.tar.gz"

  curl -fL --retry 5 --retry-all-errors -o "${SRC_ROOT}/python-ios.tar.gz" "$xcframe_url"
  rm -rf "${SRC_ROOT}/python-ios"; mkdir -p "${SRC_ROOT}/python-ios"
  tar -xzf "${SRC_ROOT}/python-ios.tar.gz" -C "${SRC_ROOT}/python-ios"

  local xcframe="$(find "${SRC_ROOT}/python-ios" -type d -name 'Python.xcframework' | head -1)"
  local out="${STAGE_ROOT}/python/${PLATFORM}/${ARCH_DIR}"
  rm -rf "$out"; mkdir -p "$out"
  cp -a "$xcframe" "$out/Python.xcframework"

  # 尝试从 xcframework 提取头文件
  local slice="$(find "$xcframe" -type d -name 'ios-arm64' | head -1)"
  [ -d "$slice/include" ] && cp -a "$slice/include" "$out/include"
  [ -d "$slice/lib" ] && cp -a "$slice/lib" "$out/lib"

  [ -d "$out/Python.xcframework" ] || { echo "[python] 错误：未生成 Python.xcframework" >&2; exit 1; }
  if [ ! -f "$out/include/python3.12/Python.h" ] && [ ! -f "$out/include/Python.h" ]; then
    echo "[python] 错误：未生成 Python.h" >&2; exit 1
  fi

  echo "[python] 完成（iOS xcframework，已通过严格检查）"
}

build_python
