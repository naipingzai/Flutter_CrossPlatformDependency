#!/usr/bin/env bash
# ============================================================
# platforms/android.sh —— Android 平台配置（4 架构）
# ============================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common/functions.sh"

PLATFORM="android"
export PLATFORM

# 检查 NDK
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  echo "[Android] 错误：请设置 ANDROID_NDK_HOME" >&2; exit 1
fi

API_LEVEL="${API_LEVEL:-21}"
export API_LEVEL

# 架构 → triple 映射
declare -A ANDROID_ARCH_TRIPLE=(
  [armeabi-v7a]="armv7a-linux-androideabi"
  [arm64-v8a]="aarch64-linux-android"
  [x86]="i686-linux-android"
  [x86_64]="x86_64-linux-android"
)

ANDROID_ARCHS="armeabi-v7a arm64-v8a x86 x86_64"

for arch in $ANDROID_ARCHS; do
  export ARCH="$arch"
  export ARCH_DIR="$arch"

  triple="${ANDROID_ARCH_TRIPLE[$arch]}"
  export CROSS_PREFIX="${triple}-${API_LEVEL}-"
  export CC="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin/${triple}${API_LEVEL}-clang"
  export CXX="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin/${triple}${API_LEVEL}-clang++"
  export AR="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
  export SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

  unset EXTRA_CFLAGS EXTRA_LDFLAGS HOST_TRIPLE BUILD_PYTHON 2>/dev/null || true

  for lib in ffmpeg miniz stb_image sqlite python; do
    echo "========== 编译 ${lib} (Android ${arch}) =========="
    bash "$(dirname "${BASH_SOURCE[0]}")/../libs/${lib}.sh"
  done

  # 发布各库（独立）
  for lib in ffmpeg miniz stb_image sqlite python; do
    stage_release "$lib"
  done
  python_check "$(platform_cc)"
done
