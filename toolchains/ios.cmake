# ============================================================
# ios.cmake - iOS CMake 工具链（参考）
# ============================================================
# 供依赖仓库内需要使用 CMake 构建的第三方库使用。
# FFmpeg 本身使用 ./configure + make，不适用本文件。
# 用法：
#   cmake -DCMAKE_TOOLCHAIN_FILE=ios.cmake -DIOS_PLATFORM=DEVICE ...
# ============================================================

set(IOS_PLATFORM "DEVICE" CACHE STRING "DEVICE / SIMULATOR")
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_DEPLOYMENT_TARGET 12.0)

if(IOS_PLATFORM STREQUAL "DEVICE")
  set(CMAKE_OSX_ARCHITECTURES arm64)
  set(CMAKE_XCODE_EFFECTIVE_PLATFORMS "-iphoneos")
else()
  set(CMAKE_OSX_ARCHITECTURES arm64 x86_64)
  set(CMAKE_XCODE_EFFECTIVE_PLATFORMS "-iphonesimulator")
endif()

set(CMAKE_CROSSCOMPILING TRUE)
