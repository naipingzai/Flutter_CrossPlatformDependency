#!/usr/bin/env bash
# ============================================================
# build_ios.sh - 编译 iOS 静态库 (arm64 真机)
# ============================================================
# 在 macos-latest runner 上使用 Xcode SDK 交叉编译 iOS arm64。
# 产出：${STAGE_ROOT}/ffmpeg/ios/arm64/{include,lib}
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

IOS_SDK="${IOS_SDK:-iphoneos}"          # 真机
ARCH="${IOS_ARCH:-arm64}"

sysroot="$(xcrun --sdk "${IOS_SDK}" --show-sdk-path)"
cc="$(xcrun --sdk "${IOS_SDK}" --find clang)"

echo "[ffmpeg] ==== 构建 iOS ${ARCH} (${IOS_SDK}) ===="
ffmpeg_fetch_source
export STAGE_INSTALL="${STAGE_ROOT}/install-ios-${ARCH}"
rm -rf "${STAGE_INSTALL}"
build_dir="${FFMPEG_SOURCE_ROOT}/build-ios-${ARCH}"
mkdir -p "${build_dir}" && cd "${build_dir}"

# iOS 需关闭汇编（避免生成不兼容符号），并启用交叉编译
"${FFMPEG_SOURCE_ROOT}/${FFMPEG_SRC_DIR}/configure" \
  $(ffmpeg_common_config) \
  --enable-cross-compile \
  --target-os=darwin \
  --arch="${ARCH}" \
  --cc="${cc}" \
  --sysroot="${sysroot}" \
  --disable-asm

make $(ffmpeg_make_flags)
make install
ffmpeg_stage_output "ios" "${ARCH}"
echo "[ffmpeg] iOS 构建完成"
