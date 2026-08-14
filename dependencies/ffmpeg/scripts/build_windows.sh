#!/usr/bin/env bash
# ============================================================
# build_windows.sh - 编译 Windows x86_64 静态库
# ============================================================
# 在 windows-latest runner 上执行。使用 msys2 + mingw-w64 gcc
# 交叉编译，生成可供 MSVC/CMake 链接的静态库。
# 产出：${STAGE_ROOT}/ffmpeg/windows/x86_64/{include,lib}
# ============================================================

set -euo pipefail

# Windows runner 使用 Git Bash，RUNNER_TEMP 可能含反斜杠，统一处理
RUNNER_TEMP="${RUNNER_TEMP:-/tmp}"
RUNNER_TEMP="${RUNNER_TEMP//\\//}"
export FFMPEG_SOURCE_ROOT="${FFMPEG_SOURCE_ROOT:-${RUNNER_TEMP}/ffmpeg-src}"
export STAGE_ROOT="${STAGE_ROOT:-${RUNNER_TEMP}/ffmpeg-stage}"

# 脚本所在目录（Windows 下可能是 /d/... 形式）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# 通过 msys2 shell 执行（本脚本期望在 MSYS2 mingw64 环境中运行）
echo "[ffmpeg] 准备 Windows 构建环境"
# 在 msys2/mingw 下 gcc 即 mingw-w64 gcc
command -v gcc >/dev/null || { echo "未找到 gcc (mingw-w64)。请在 MSYS2 MinGW64 环境运行"; exit 1; }

# 在 msys2/mingw64 环境下原生构建 Windows（非交叉编译），
# 直接使用 PATH 中的 gcc / ar / ranlib，无需 cross-prefix
echo "[ffmpeg] ==== 构建 Windows x86_64 ===="
ffmpeg_fetch_source
export STAGE_INSTALL="${STAGE_ROOT}/install-windows-x86_64"
rm -rf "${STAGE_INSTALL}"
build_dir="${FFMPEG_SOURCE_ROOT}/build-windows-x86_64"
mkdir -p "${build_dir}" && cd "${build_dir}"
"${FFMPEG_SOURCE_ROOT}/${FFMPEG_SRC_DIR}/configure" \
  $(ffmpeg_common_config) \
  --arch=x86_64 \
  --target-os=mingw32
make $(ffmpeg_make_flags)
make install
ffmpeg_stage_output "windows" "x86_64"
echo "[ffmpeg] Windows 构建完成"
