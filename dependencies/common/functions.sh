#!/usr/bin/env bash
# ============================================================
# common/functions.sh —— 通用函数库
# 提供：下载解压、平台判断、编译辅助、产物归集等
# ============================================================

# ---- 下载与解压 ----
dl_extract() {
  # $1=dep $2=url $3=src_dir $4=tarball
  local dep="$1" url="$2" src_dir="$3" tarball="$4"
  local root="${SRC_ROOT}/${dep}"
  if [ -d "${root}/${src_dir}" ]; then echo "[${dep}] 源码已存在"; return; fi
  mkdir -p "${root}"
  curl -fL --retry 5 --retry-delay 3 --retry-all-errors -o "${root}/${tarball}" "${url}"
  local t p
  if command -v cygpath >/dev/null 2>&1; then
    t="$(cygpath -u "${root}/${tarball}")"; p="$(cygpath -u "${root}")"
  else
    t="${root}/${tarball}"; p="${root}"
  fi
  if [[ "$tarball" == *.tar.xz ]] || [[ "$tarball" == *.txz ]]; then
    tar -xJf "$t" -C "$p"
  else
    tar -xzf "$t" -C "$p"
  fi
  echo "[${dep}] 就绪: ${root}/${src_dir}"
}

# ---- 平台工具链 ----
platform_cc()  { echo "${CC:-cc}"; }
platform_ar()  { echo "${AR:-ar}"; }

# FFmpeg target_os 映射
platform_target_os() {
  case "$PLATFORM" in
    linux) echo linux;;
    windows) echo mingw32;;
    macos) echo darwin;;
    android) echo android;;
    ios) echo darwin;;
  esac
}

# 是否需要交叉编译标记（FFmpeg autoconf 用）
platform_needs_cross() {
  case "$PLATFORM" in
    macos|android|ios) echo 1;;
    *) echo 0;;
  esac
}

# ---- 动态库扩展名 ----
shared_ext() {
  case "$PLATFORM" in
    macos|ios) echo "dylib";;
    windows) echo "dll";;
    *) echo "so";;
  esac
}

# ---- 从目标文件创建动态库 ----
create_shared_lib() {
  local cc="$1" output="$2"; shift 2
  local objs=("$@")
  case "$PLATFORM" in
    macos|ios)
      "${cc}" -dynamiclib -o "$output" "${objs[@]}"
      ;;
    *)
      "${cc}" -shared -o "$output" "${objs[@]}"
      ;;
  esac
}

# ---- 归集单一库产物到 stage ----
# 调用后产物位于 ${STAGE_ROOT}/<lib>/<PLATFORM>/<ARCH_DIR>/{include,lib}
stage_lib() {
  local lib="$1"
  local out="${STAGE_ROOT}/${lib}/${PLATFORM}/${ARCH_DIR}"
  rm -rf "$out"; mkdir -p "$out";
}

# ---- 合并所有库到一个平台目录 ----
stage_platform() {
  local out="${STAGE_ROOT}/${PLATFORM}/${ARCH_DIR}"
  rm -rf "$out"; mkdir -p "$out/include" "$out/lib"
  for dep in $DEP_LIBS; do
    local d="${STAGE_ROOT}/${dep}/${PLATFORM}/${ARCH_DIR}"
    [ -d "$d" ] || continue
    cp -a "$d/include/." "$out/include/" 2>/dev/null || true
    cp -a "$d/lib/." "$out/lib/" 2>/dev/null || true
    # iOS xcframework 特殊处理
    if [ -d "$d/Python.xcframework" ]; then
      cp -a "$d/Python.xcframework" "$out/"
    fi
  done
  echo "[platform] 合并完成: ${out}"
}

# ---- 发布单一库到 release 目录 ----
# 调用：stage_release <lib>
# 产物位于：release/<lib>/<PLATFORM>/<ARCH_DIR>/{include,lib}
stage_release() {
  local lib="$1"
  local src="${STAGE_ROOT}/${lib}/${PLATFORM}/${ARCH_DIR}"
  local out="${DEP_ROOT}/../release/${lib}/${PLATFORM}/${ARCH_DIR}"
  rm -rf "$out"; mkdir -p "$out/include" "$out/lib"
  cp -a "$src/include/." "$out/include/" 2>/dev/null || true
  cp -a "$src/lib/." "$out/lib/" 2>/dev/null || true
  rm -rf "$out/lib/pkgconfig" 2>/dev/null || true
  # iOS xcframework
  if [ -d "${src}/Python.xcframework" ]; then
    cp -a "${src}/Python.xcframework" "$out/"
  fi
  echo "[release] ${lib} 产物已发布到: ${out}"
  echo "[release] ${lib} 静态库:"
  ls -1 "$out/lib/"*.a 2>/dev/null || echo "  (无)"
  echo "[release] ${lib} 动态库:"
  ls -1 "$out/lib/"*."$(shared_ext)" 2>/dev/null || echo "  (无)"
  if [ -d "$out/Python.xcframework" ]; then
    echo "[release] ${lib} xcframework: Python.xcframework"
  fi
}

# ---- Android PIC 校验 ----
android_check_pic() {
  local lib_path="$1"
  if command -v readelf >/dev/null 2>&1; then
    if readelf -d "$lib_path" >/dev/null 2>&1 && readelf -d "$lib_path" | grep -q "TEXTREL"; then
      echo "[Android PIC] 错误：$lib_path 包含 TEXTREL（非 PIC），请使用 -fPIC 编译" >&2
      return 1
    fi
  fi
  return 0
}

# ---- Python 产物校验 ----
python_check() {
  local cc="$1"
  local out="${STAGE_ROOT}/${PLATFORM}/${ARCH_DIR}"
  if [ -d "$out/Python.xcframework" ]; then
    # iOS xcframework 不需要编译测试
    echo "[python check] iOS xcframework 跳过编译测试"
    return 0
  fi
  if [ "$PLATFORM" = "windows" ]; then
    # Windows 预编译包，检查 DLL 存在
    if ls "$out"/python*.dll >/dev/null 2>&1; then
      echo "[python check] Windows DLL 存在"
      return 0
    fi
    echo "[python check] 警告：未找到 Python DLL" >&2
    return 0
  fi
  # 其他平台：编译测试程序
  local test_c="${STAGE_ROOT}/python_check.c"
  cat > "$test_c" <<'EOF'
#include <Python.h>
int main() {
    Py_Initialize();
    Py_Finalize();
    return 0;
}
EOF
  local test_bin="${STAGE_ROOT}/python_check_bin"
  local include_dirs="-I${out}/include -I${out}/include/python3.12"
  if [ -d "${out}/include/Python.h" ]; then
    include_dirs="-I${out}/include"
  fi
  "${cc}" "$test_c" ${include_dirs} -L"${out}/lib" -lpython3.12 -o "$test_bin" 2>/dev/null \
    || "${cc}" "$test_c" ${include_dirs} -L"${out}/lib" -lpython3.11 -o "$test_bin" 2>/dev/null \
    || "${cc}" "$test_c" ${include_dirs} "${out}/lib/libpython3.12.a" -o "$test_bin" 2>/dev/null \
    || "${cc}" "$test_c" ${include_dirs} "${out}/lib/libpython3.11.a" -o "$test_bin" 2>/dev/null \
    || true
  rm -f "$test_c" "$test_bin"
  echo "[python check] 完成"
}

# ---- 带平台参数的直接编译辅助 ----
# 编译单个 .c → .o
compile_object() {
  local cc="$1" src="$2" obj="$3"
  shift 3
  local cflags=("$@")
  local cmd=("${cc}" "${cflags[@]}" -c "$src" -o "$obj")
  if [ -n "${SYSROOT:-}" ]; then
    # 在 -c 之前插入 -isysroot
    local new_cmd=("${cc}")
    for flag in "${cflags[@]}"; do
      new_cmd+=("$flag")
    done
    new_cmd+=("-isysroot" "${SYSROOT}" -c "$src" -o "$obj")
    cmd=("${new_cmd[@]}")
  fi
  "${cmd[@]}"
}
