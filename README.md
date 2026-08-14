# ============================================================
# README - Flutter_CrossPlatformDependency
# ============================================================
#
# 本仓库专门负责第三方原生 C/C++ 库的跨平台静态编译，
# 并通过 GitHub Actions 构建、发布编译产物。
#
# APP 仓库不维护第三方库的跨平台编译逻辑，
# 只从本仓库的 Release 下载对应平台的 include/ 与 lib/ 使用。
#
# == 架构 ==
#   平台配置集中在 .github/workflows/*.yml（runner / 工具链 / ARCH / 参数）。
#   构建逻辑复用 scripts/common.sh 通用引擎（平台无业务分支）。
#   每个依赖一个目录：dependencies/<dep>/（build.sh + dependency.yaml）。
#
#   新增依赖步骤：
#     1. mkdir dependencies/<dep>/ 并编写 build.sh（设置源码常量 + 依赖 configure 参数）
#     2. 编写 dependency.yaml（版本 / 平台 / 产物结构）
#     3. 在 .github/workflows/ 新增 <dep>.yml（平台 Job 矩阵 + Release 发布）
#
# == 支持的平台（64 位） ==
#   Windows  x86_64
#   Linux    x86_64
#   macOS    arm64（Apple Silicon）
#   Android  arm64-v8a
#   iOS      arm64（真机）
#
# == 目录结构 ==
#   scripts/
#     common.sh            通用构建引擎（autoconf 型：下载/configure/make/整理）
#   dependencies/
#     ffmpeg/
#       build.sh           依赖构建入口（复用 common.sh）
#       dependency.yaml    依赖配置（版本/平台/产物结构）
#   toolchains/            （预留 CMake 型依赖的工具链）
#   .github/workflows/
#     build_ffmpeg.yml     平台矩阵 + 发布 Release
#
# == 如何触发构建 ==
#   - 手动：Actions → 对应 workflow → Run workflow
#   - 或推送 tag（如 ffmpeg-* 触发 build_ffmpeg.yml）
#
# == 产物统一结构 ==
#   ffmpeg/<plat>/<arch>/include/
#   ffmpeg/<plat>/<arch>/lib/
#   其中 <plat>: windows / linux / macos / android / ios
#        <arch>: x86_64 / arm64 / universal / arm64-v8a
