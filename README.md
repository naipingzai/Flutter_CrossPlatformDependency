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
# 支持的平台：
#   Windows  x86_64
#   Linux    x86_64 / aarch64
#   macOS    universal (arm64 + x86_64)
#   Android  armeabi-v7a / arm64-v8a / x86 / x86_64
#   iOS      arm64（真机）
#
# == 目录结构 ==
#   dependencies/
#     ffmpeg/
#       dependency.yaml      依赖配置（版本、平台、输出结构）
#       scripts/
#         common.sh          共用逻辑（下载源码、configure、整理产物）
#         build_linux.sh
#         build_windows.sh
#         build_macos.sh
#         build_android.sh
#         build_ios.sh
#       cmake/               预留：未来 CMake 型依赖的配置
#   toolchains/
#     android.cmake          Android NDK CMake 工具链
#     ios.cmake              iOS CMake 工具链
#   .github/workflows/
#     build_ffmpeg.yml       编译 FFmpeg 并发布 Release
#
# == 如何触发 FFmpeg 构建 ==
#   - 手动：GitHub Actions 页面点击 "Run workflow"（workflow_dispatch）
#   - 或推送 tag：git tag ffmpeg-7.1 && git push origin ffmpeg-7.1
#
# 构建完成后自动把产物打包上传到 Release（tag: ffmpeg-n7.1）。
#
# == 产物统一结构 ==
#   ffmpeg/<plat>/<arch>/include/
#   ffmpeg/<plat>/<arch>/lib/
#   其中 <plat>: windows / linux / macos / android / ios
#        <arch>: x86_64 / aarch64 / universal / arm64 / armeabi-v7a / ...
#
# 后续新增依赖（sqlite / openssl / libarchive / ...）时，
# 在 dependencies/ 下新建同名目录，遵循相同规范即可。
