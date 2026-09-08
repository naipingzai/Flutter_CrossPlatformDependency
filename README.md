# Flutter_CrossPlatformDependency

> 第三方原生 C/C++ 库的**跨平台编译**仓库。
> 只负责「获取源码 → 编译 → 发布产物」，不参与任何 APP 业务逻辑。
> 同时编译**静态库（.a）**和**动态库（.so/.dylib/.dll）**，产物输出到 `release/` 目录。

## 0. 背景：静态库与动态库，各平台对原生代码形态的支持

本仓库把第三方库统一编译为**静态库**和**动态库**，APP 可按需选择使用哪种形态。
各平台对原生代码的加载方式差异如下：

| 平台 | 原生代码如何进入 APP | Dart/运行时如何找到它 | 是否需要 PIC | 静态库扩展名 | 动态库扩展名 |
|------|---------------------|----------------------|:---:|:---:|:---:|
| Linux | 静态链接进**可执行文件** 或 加载 `.so` | `DynamicLibrary.process()` / `.open()` | 是（.so 必须） | `.a` | `.so` |
| Windows | 静态链接进 **.exe** 或 加载 `.dll` | `DynamicLibrary.process()` / `.open()` | 否 | `.a` | `.dll` |
| macOS | 静态链接进**可执行文件** 或 加载 `.dylib` | `DynamicLibrary.process()` / `.open()` | 是（.dylib 必须） | `.a` | `.dylib` |
| Android | 打包进共享库壳 **`libfileops.so`** 或加载 `.so` | `DynamicLibrary.open('libfileops.so')` | **是（强制）** | `.a` | `.so` |
| iOS | 静态链接进 **Mach-O** | `DynamicLibrary.process()` | 否 | `.a` | `.dylib` |

### 关键差异说明

1. **iOS 动态库限制**：App Store 禁止运行时加载第三方动态库，原生代码必须
   静态链接进最终 Mach-O。→ **iOS 发布时使用静态库 `.a`**，动态库仅用于开发/测试。
2. **Android 的 `.so` 壳 + PIC**：Android 无可执行文件，原生代码必须打包成
   共享库 `libfileops.so`（Dart 通过 `DynamicLibrary.open` 加载）。**共享库在
   ARM64 上强制要求所有代码为位置无关（PIC）**。若静态库缺 `-fPIC`，链接时会报：
   ```
   relocation R_AARCH64_ADR_PREL_PG_HI21 cannot be used against symbol ...
   recompile with -fPIC
   ```
   因此 **Android 的 FFmpeg 必须带 `-fPIC`**（已通过 `--enable-pic` + workflow
   注入 `-fPIC` 保证，并在脚本末尾做 PIC 校验，非 PIC 直接构建失败）。
3. **桌面/iOS 的 PIC**：静态链接进可执行文件/Mach-O 不要求 PIC，但动态库
   （.so/.dylib）必须使用 PIC 代码。本仓库所有编译已统一加 `-fPIC`。
4. **结论**：跨平台的"麻烦"主要来自 Android 的 `.so` 壳与 PIC 要求，以及 iOS 的
   静态链接强制——这是移动多平台 + 大型原生库的固有成本，与前端框架（Flutter）
   无关。本仓库用「一套静态库 + 动态库 + 矩阵式构建脚本」把这份成本收敛到最标准形态。

---

## 工程描述

本仓库把 APP 需要的第三方原生库（ffmpeg / miniz / stb_image / sqlite / python）
在 **5 个目标平台**（linux / windows / macos / android / ios）上编译为**静态库和动态库**，
并发布到 `release/` 目录中，按平台区分、按库分开。

APP 仓库（如 `Flutter_FileManager`）**不维护第三方库的跨平台编译逻辑**，
只从本仓库 `release/` 目录获取对应平台的产物使用（或直接 vendor 进 APP 工程）。

---

## 1. 设计原则

### dependencies — 矩阵式结构

采用 **平台 × 库** 的矩阵式架构，将"平台配置"与"库编译逻辑"正交分离：

```
dependencies/
├── build.sh              # 统一入口：bash build.sh <platform>
├── common/
│   ├── config.sh         # 全局配置（版本、URL、通用标志）
│   └── functions.sh      # 通用函数（dl_extract, stage_lib, create_shared_lib 等）
├── libs/                 # 库编译逻辑（平台无关）
│   ├── ffmpeg.sh
│   ├── miniz.sh
│   ├── stb_image.sh
│   ├── sqlite.sh
│   └── python.sh
├── platforms/            # 平台配置（工具链、架构循环）
│   ├── linux.sh
│   ├── windows.sh
│   ├── macos.sh
│   ├── android.sh        # 循环 4 架构
│   └── ios.sh
```

**新增一个库** = 只需在 `libs/` 下新增一个 `.sh` 文件 + 在 `config.sh` 的 `LIBS_LIST`
中注册名称，所有平台自动获得该库的编译能力。

**新增一个平台** = 只需在 `platforms/` 下新增一个 `.sh` 文件，设置工具链环境变量，
遍历所有库进行编译。

### 设计优势

| 特性 | 旧版（按平台自包含） | 新版（矩阵式） |
|------|---------------------|---------------|
| 新增库 | 需修改 5 个平台脚本 | 只需 1 个库脚本 + 1 行注册 |
| 新增平台 | 需复制全部库编译逻辑 | 只需 1 个平台脚本 |
| 代码复用 | 0%，大量重复 | 100%，库脚本共享 |
| 维护成本 | 5N（N=库数） | M+N（M=平台数） |

---

## 2. 目录结构

```text
Flutter_CrossPlatformDependency/
├── dependencies/                   # 矩阵式结构
│   ├── build.sh                    # 统一入口
│   ├── common/
│   │   ├── config.sh               # 全局配置
│   │   └── functions.sh            # 通用函数
│   ├── libs/                       # 库编译脚本
│   │   ├── ffmpeg.sh
│   │   ├── miniz.sh
│   │   ├── stb_image.sh
│   │   ├── sqlite.sh
│   │   └── python.sh
│   └── platforms/                  # 平台配置脚本
│       ├── linux.sh
│       ├── windows.sh
│       ├── macos.sh
│       ├── android.sh
│       └── ios.sh
├── release/                        # 构建产物输出目录
│   ├── linux/x86_64/
│   ├── windows/x86_64/
│   ├── macos/arm64/
│   ├── macos/x86_64/
│   ├── android/armeabi-v7a/
│   ├── android/arm64-v8a/
│   ├── android/x86/
│   ├── android/x86_64/
│   └── ios/arm64/
└── .github/workflows/
    └── build_platforms.yml
```

### 执行流程

```
bash dependencies/build.sh <platform>
  → 加载 common/config.sh + common/functions.sh
  → 加载 platforms/<platform>.sh
  → 遍历 ARCH 列表，对每个架构：
      → 设置工具链 (CC/CXX/AR/SYSROOT)
      → 遍历 LIBS_LIST，对每个库：
          → 执行 libs/<lib>.sh
          → stage_lib 到临时目录
      → stage_platform 合并为平台产物
      → stage_release 输出到 release/
```

---

## 3. 各平台编译的库

| 库 | 构建方式 | 静态库产物 | 动态库产物 |
|----|---------|------|------|
| ffmpeg | autoconf（按平台 target-os，交叉加 `--enable-cross-compile`，`--enable-static --enable-shared`） | `libavformat.a` `libavcodec.a` `libavutil.a` `libswscale.a` `libswresample.a` | `libavformat.so/.dylib/.dll` 等 |
| miniz | 直接编译 amalgamation（-fPIC） | `libminiz.a` | `libminiz.so/.dylib/.dll` |
| stb_image | 直接编译（-fPIC） | `libstb_image.a` | `libstb_image.so/.dylib/.dll` |
| sqlite | 直接编译 sqlite3.c（-fPIC） | `libsqlite3.a` | `libsqlite3.so/.dylib/.dll` |
| python | linux/macos autoconf（原生，已验证）；windows 官方 embeddable；android 交叉、ios Apple-support（best-effort） | `libpython3.12.a` / embeddable / `.xcframework` | （python 通常仅静态） |

> **python**：linux/macos/windows 真实编译；**android/ios 交叉编译 CPython 较难**
> （configure 无法运行目标二进制），为 best-effort——失败会明确报错并跳过该库，**不影响**
> ffmpeg/miniz/stb_image/sqlite 四个核心库及 linux/macos/windows 的 python。

---

## 4. 新增一个库（流程）

矩阵式结构下，新增一个库只需 3 步：

### 步骤 1：在 `libs/` 下创建编译脚本

```bash
# libs/mylib.sh
# 引用全局配置和函数（由平台脚本在调用前 source）
build_mylib() {
  local DEP_SRC_DIR="mylib-1.0"
  dl_extract mylib "https://.../mylib-1.0.tar.gz" "$DEP_SRC_DIR" "mylib.tar.gz"

  local cc ar; cc="$(platform_cc)"; ar="$(platform_ar)"
  local inst="${STAGE_ROOT}/mylib-inst"; rm -rf "$inst"; mkdir -p "$inst/include" "$inst/lib"
  local bd="${SRC_ROOT}/mylib/build"; rm -rf "$bd"; mkdir -p "$bd"

  "${cc}" -O2 -fPIC -c "${SRC_ROOT}/mylib/${DEP_SRC_DIR}/mylib.c" -o "$bd/mylib.o"
  ${ar} rcs "$inst/lib/libmylib.a" "$bd/mylib.o"
  create_shared_lib "${cc}" "$inst/lib/libmylib.$(shared_ext)" "$bd/mylib.o"
  cp "${SRC_ROOT}/mylib/${DEP_SRC_DIR}/mylib.h" "$inst/include/"
  stage_lib mylib
  echo "[mylib] 完成"
}
build_mylib
```

### 步骤 2：在 `common/config.sh` 中注册

```bash
LIBS_LIST="ffmpeg miniz stb_image sqlite python mylib"
```

### 步骤 3：在 workflow 的 `env.DEP_LIBS` 中加入 `mylib`

所有平台自动获得该库编译能力，无需修改任何平台脚本。

---

## 5. 产物结构

构建完成后，产物自动输出到 `release/` 目录：

```text
release/
├── linux/x86_64/
│   ├── ffmpeg/   include/ + lib/ (lib*.a + lib*.so)
│   ├── miniz/    include/ + lib/
│   ├── stb_image/ include/ + lib/
│   ├── sqlite/   include/ + lib/
│   └── python/   include/ + lib/
├── windows/x86_64/
│   ├── ffmpeg/   ...
│   └── ...
├── macos/
│   ├── arm64/    ...
│   └── x86_64/   ...
├── android/
│   ├── armeabi-v7a/ ...
│   ├── arm64-v8a/   ...
│   ├── x86/         ...
│   └── x86_64/      ...
└── ios/arm64/
    ├── ffmpeg/   ...
    └── ...
```

每个库目录下包含 `include/`（头文件）和 `lib/`（静态库 + 动态库）。

---

## 6. 触发 CI

push `build-*` tag 或手动触发 `Build All Platforms`：

```bash
git tag build-1.0.0
git push origin build-1.0.0
```

修改后重新打 tag 到最新 commit 再推送即可触发重建（各平台 Release 会被覆盖更新）。

---

## 7. APP 端如何消费

### 使用静态库（推荐，尤其 iOS 发布）

从 `release/` 目录获取对应平台的 `include/` + `lib/`：

```text
release/<platform>/<arch>/<lib>/include/   # 头文件
release/<platform>/<arch>/<lib>/lib/*.a    # 静态库
```

加入头文件路径并链接静态库。

### 使用动态库

```text
release/<platform>/<arch>/<lib>/lib/*.so    # Linux/Android
release/<platform>/<arch>/<lib>/lib/*.dylib # macOS/iOS
release/<platform>/<arch>/<lib>/lib/*.dll   # Windows
```

Dart 侧通过 `DynamicLibrary.open()` 加载。

### 也可以把各平台各库合并后直接 vendor 进 APP 工程。

---

## 8. 静态库 vs 动态库选择指南

| 场景 | 推荐使用 | 原因 |
|------|---------|------|
| iOS App Store 发布 | 静态库 `.a` | Apple 禁止运行时加载第三方动态库 |
| Android APP | 动态库 `.so` | Flutter 通过 `DynamicLibrary.open` 加载 |
| Linux/Windows/macOS 桌面 | 静态库 `.a` | 静态链接进可执行文件，无需分发动态库 |
| 开发/测试/调试 | 动态库 | 修改后无需重新链接整个程序 |
