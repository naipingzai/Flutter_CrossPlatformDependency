# ============================================================
# android.cmake - Android NDK CMake 工具链
# ============================================================
# 供依赖仓库内需要使用 CMake 构建的第三方库使用。
# FFmpeg 本身使用 ./configure + make，不适用本文件。
# 用法：
#   cmake -DCMAKE_TOOLCHAIN_FILE=android.cmake \
#         -DANDROID_ABI=arm64-v8a \
#         -DANDROID_PLATFORM=android-21 ...
# ============================================================

if(NOT ANDROID_NDK_ROOT)
  set(ANDROID_NDK_ROOT "$ENV{ANDROID_NDK_ROOT}" CACHE PATH "Android NDK path")
endif()

if(NOT ANDROID_NDK_ROOT)
  message(FATAL_ERROR "未设置 ANDROID_NDK_ROOT")
endif()

set(ANDROID_PLATFORM "android-21" CACHE STRING "Android API level")
set(ANDROID_ABI "arm64-v8a" CACHE STRING "Android ABI")
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION 21)
set(CMAKE_ANDROID_ARCH_ABI "${ANDROID_ABI}")
set(CMAKE_ANDROID_NDK "${ANDROID_NDK_ROOT}")

set(CMAKE_ANDROID_STL_TYPE c++_static)
