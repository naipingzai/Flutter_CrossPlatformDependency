#!/usr/bin/env bash
# ============================================================
# build.sh —— 跨平台依赖编译统一入口
#
# 用法：
#   bash build.sh                        # 编译所有平台
#   bash build.sh linux                  # 仅编译 Linux
#   bash build.sh android ios            # 仅编译 Android + iOS
#   bash build.sh ffmpeg sqlite          # 仅编译 ffmpeg + sqlite（所有平台）
#   PLATFORM=linux bash build.sh         # 环境变量指定平台
#   DEPS="ffmpeg sqlite" bash build.sh   # 环境变量指定库
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source "./common/config.sh"
source "./common/functions.sh"

# 解析参数：区分平台名和库名
REQUESTED_PLATFORMS=()
REQUESTED_LIBS=()

for arg in "$@"; do
  case "$arg" in
    linux|windows|macos|android|ios)
      REQUESTED_PLATFORMS+=("$arg")
      ;;
    ffmpeg|miniz|stb_image|sqlite|python)
      REQUESTED_LIBS+=("$arg")
      ;;
    *)
      echo "未知参数: $arg" >&2
      echo "可用平台: linux windows macos android ios" >&2
      echo "可用库: ffmpeg miniz stb_image sqlite python" >&2
      exit 1
      ;;
  esac
done

# 环境变量覆盖
if [ ${#REQUESTED_PLATFORMS[@]} -eq 0 ] && [ -n "${PLATFORM:-}" ]; then
  REQUESTED_PLATFORMS=("$PLATFORM")
fi
if [ ${#REQUESTED_LIBS[@]} -eq 0 ] && [ -n "${DEPS:-}" ]; then
  READ_IFS="$IFS"; IFS=" "; REQUESTED_LIBS=($DEPS); IFS="$READ_IFS"
fi

# 默认值
PLATFORMS_LIST=("${REQUESTED_PLATFORMS[@]:-$ALL_PLATFORMS}")
LIBS_LIST=("${REQUESTED_LIBS[@]:-$DEP_LIBS}")

# 展开通配符
expand_platforms() {
  local result=()
  for p in "$@"; do
    if [ "$p" = "all" ] || [ "$p" = "desktop" ]; then
      result+=("linux" "windows" "macos")
    elif [ "$p" = "mobile" ]; then
      result+=("android" "ios")
    else
      result+=("$p")
    fi
  done
  echo "${result[@]}"
}

PLATFORMS_LIST=( $(expand_platforms "${PLATFORMS_LIST[@]}") )

echo "============================================================"
echo "  跨平台依赖编译 v2"
echo "  平台: ${PLATFORMS_LIST[*]}"
echo "  库:   ${LIBS_LIST[*]}"
echo "============================================================"

# 主循环：平台 × 库
for platform in "${PLATFORMS_LIST[@]}"; do
  echo ""
  echo "############################################################"
  echo "# 编译平台: ${platform}"
  echo "############################################################"
  bash "./platforms/${platform}.sh"
done

echo ""
echo "============================================================"
echo "  全部编译完成！"
echo "  产物目录: ${DEP_ROOT}/../release/"
echo "============================================================"
