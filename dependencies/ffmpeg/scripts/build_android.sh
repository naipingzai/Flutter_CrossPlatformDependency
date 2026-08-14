#!/usr/bin/env bash
# ============================================================
# build_android.sh - 编译 Android 各 ABI 静态库
# ============================================================
# 使用 Android NDK 交叉编译 armeabi-v7a / arm64-v8a / x86 / x86_64。
# NDK 由 workflow 提供（android-ndk r27）。串行构建，每个 ABI
# 使用独立 STAGE_INSTALL 前缀。
# 产出：${STAGE_ROOT}/ffmpeg/android/<abi>/{include,lib}
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

MIN_SDK="${MIN_SDK:-21}"
NDK_ROOT="${NDK_ROOT:?需要设置 ANDROID_NDK_ROOT / NDK_ROOT 环境变量}"

# NDK 工具链路径（r27 为 NDK 自带 clang，无独立 toolchain 目录）
TOOLCHAIN="${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64"
API_LEVEL="${MIN_SDK}"

# 各 ABI 的工具链前缀
declare -A TRIPLE=(
  [armeabi-v7a]="armv7a-linux-androideabi"
  [arm64-v8a]="aarch64-linux-android"
  [x86]="i686-linux-android"
  [x86_64]="x86_64-linux-android"
)
declare -A CFLAGS_EXTRA=(
  [armeabi-v7a]="-march=armv7-a -mfpu=neon -mfloat-abi=softfp"
  [arm64-v8a]=""
  [x86]=""
  [x86_64]=""
)

build_abi() {
  local abi="$1"
  local triple="${TRIPLE[$abi]}"
  local cc="${TOOLCHAIN}/bin/${triple}${API_LEVEL}-clang"
  local cxx="${TOOLCHAIN}/bin/${triple}${API_LEVEL}-clang++"
  local arch
  case "$abi" in
    armeabi-v7a) arch="armv7-a" ;;
    arm64-v8a)   arch="aarch64" ;;
    x86)         arch="i686" ;;
    x86_64)      arch="x86_64" ;;
  esac

  echo "[ffmpeg] ==== 构建 Android ${abi} (arch=${arch}) ===="
  export STAGE_INSTALL="${STAGE_ROOT}/install-android-${abi}"
  rm -rf "${STAGE_INSTALL}"
  local build_dir="${FFMPEG_SOURCE_ROOT}/build-android-${abi}"
  mkdir -p "${build_dir}" && cd "${build_dir}"

  local extra_cflags=(-DANDROID -fPIC ${CFLAGS_EXTRA[$abi]})
  local extra_ldflags="-L${TOOLCHAIN}/sysroot/usr/lib/${triple}/${API_LEVEL}"
  # x86/x86_64 需要 nasm 才能编手写汇编；NDK 不带 nasm，关闭以产出有效库
  local arch_opts=()
  if [ "$arch" = "i686" ] || [ "$arch" = "x86_64" ]; then
    arch_opts+=(--disable-x86asm)
  fi

  "${FFMPEG_SOURCE_ROOT}/${FFMPEG_SRC_DIR}/configure" \
    $(ffmpeg_common_config) \
    --enable-cross-compile \
    --target-os=android \
    --arch="${arch}" \
    --cc="${cc}" \
    --cxx="${cxx}" \
    --extra-cflags="${extra_cflags[*]}" \
    --extra-ldflags="${extra_ldflags}" \
    --sysroot="${TOOLCHAIN}/sysroot" \
    "${arch_opts[@]}"

  make $(ffmpeg_make_flags)
  make install
  ffmpeg_stage_output "android" "${abi}"
}

ffmpeg_fetch_source

# 串行构建 4 个 ABI
for abi in "${!TRIPLE[@]}"; do
  build_abi "${abi}"
done
echo "[ffmpeg] Android 构建完成"
