#!/usr/bin/env bash
# ============================================================
# build_macos.sh - 编译 macOS universal 静态库 (arm64 + x86_64)
# ============================================================
# 在 macos-latest runner 上执行。分别编译 arm64 与 x86_64，
# 再用 lipo 合并为 universal 静态库。
# 产出：${STAGE_ROOT}/ffmpeg/macos/universal/{include,lib}
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

build_arch() {
  local arch="$1"
  local sysroot
  sysroot="$(xcrun --sdk macosx --show-sdk-path)"
  echo "[ffmpeg] ==== 构建 macOS ${arch} ===="
  export STAGE_INSTALL="${STAGE_ROOT}/install-macos-${arch}"
  rm -rf "${STAGE_INSTALL}"
  local build_dir="${FFMPEG_SOURCE_ROOT}/build-macos-${arch}"
  mkdir -p "${build_dir}" && cd "${build_dir}"
  "${FFMPEG_SOURCE_ROOT}/${FFMPEG_SRC_DIR}/configure" \
    $(ffmpeg_common_config) \
    --arch="${arch}" \
    --target-os=darwin \
    --cc="$(xcrun --sdk macosx --find clang)" \
    --sysroot="${sysroot}" \
    --enable-cross-compile
  make $(ffmpeg_make_flags)
  make install
  # 暂存该架构的 lib 与 include（include 两架构一致，取 arm64 的）
  local lib_dir="${STAGE_ROOT}/macos-libs-${arch}"
  rm -rf "${lib_dir}" && mkdir -p "${lib_dir}"
  cp -a "${STAGE_INSTALL}/lib" "${lib_dir}/lib"
  cp -a "${STAGE_INSTALL}/include" "${lib_dir}/include"
}

ffmpeg_fetch_source

# 依次构建 arm64 与 x86_64（共享源码，串行避免 install 冲突）
build_arch "arm64"
build_arch "x86_64"

echo "[ffmpeg] ==== lipo 合并 universal ===="
out="${STAGE_ROOT}/ffmpeg/macos/universal"
rm -rf "${out}"
mkdir -p "${out}/lib"
for lib in "${STAGE_ROOT}"/macos-libs-arm64/lib/libav*.a; do
  base="$(basename "${lib}")"
  lipo -create \
    "${STAGE_ROOT}/macos-libs-arm64/lib/${base}" \
    "${STAGE_ROOT}/macos-libs-x86_64/lib/${base}" \
    -output "${out}/lib/${base}"
done
cp -a "${STAGE_ROOT}/macos-libs-arm64/include" "${out}/include"

echo "[ffmpeg] macOS universal 构建完成: ${out}"
