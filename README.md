# Flutter_CrossPlatformDependency

> 第三方原生 C/C++ 库的**跨平台静态编译**仓库。
> 只负责「获取源码 → 编译 → 发布产物」，不参与任何 APP 业务逻辑。

## 0. 背景：为什么是「静态库」，各平台对原生代码形态的支持

本仓库把第三方库统一编译为**静态库 `.a`**，因为这是唯一能在 5 个平台统一交付
且被 iOS 强制要求的形式。各平台对原生代码的加载方式差异如下：

| 平台 | 原生代码如何进入 APP | Dart/运行时如何找到它 | 是否需要 PIC | FFmpeg 形态 |
|------|---------------------|----------------------|:---:|:---:|
| Linux | 静态链接进**可执行文件** (Flutter runner) | `DynamicLibrary.process()` 查进程符号表 | 否 | 静态 `.a` |
| Windows | 静态链接进 **.exe** | `DynamicLibrary.process()` | 否 | 静态 `.a` |
| macOS | 静态链接进**可执行文件** | `DynamicLibrary.process()` | 否 | 静态 `.a` |
| Android | 打包进共享库壳 **`libfileops.so`** | `DynamicLibrary.open('libfileops.so')` | **是（强制）** | 静态 `.a` |
| iOS | 静态链接进 **Mach-O** | `DynamicLibrary.process()` | 否 | 静态 `.a` |

### 关键差异说明

1. **iOS 强制静态库**：App Store 禁止运行时加载第三方动态库，原生代码必须
   静态链接进最终 Mach-O。→ FFmpeg 只能编 `.a`。
2. **Android 的 `.so` 壳 + PIC**：Android 无可执行文件，原生代码必须打包成
   共享库 `libfileops.so`（Dart 通过 `DynamicLibrary.open` 加载）。**共享库在
   ARM64 上强制要求所有代码为位置无关（PIC）**。若静态库缺 `-fPIC`，链接时会报：
   ```
   relocation R_AARCH64_ADR_PREL_PG_HI21 cannot be used against symbol ...
   recompile with -fPIC
   ```
   因此 **Android 的 FFmpeg 必须带 `-fPIC`**（已通过 `--enable-pic` + workflow
   注入 `-fPIC` 保证，并在脚本末尾做 PIC 校验，非 PIC 直接构建失败）。
3. **桌面/iOS 无需 PIC**：静态链接进可执行文件/Mach-O 不要求 PIC，这也是同一套
   FFmpeg 源码在 Linux 能过、Android 却报错的原因。
4. **结论**：跨平台的"麻烦"主要来自 Android 的 `.so` 壳与 PIC 要求，以及 iOS 的
   静态链接强制——这是移动多平台 + 大型原生库的固有成本，与前端框架（Flutter）
   无关。本仓库用「一套静态库 + 每平台自包含脚本」把这份成本收敛到最标准形态。

---

## 工程描述

本仓库把 APP 需要的第三方原生库（ffmpeg / miniz / stb_image / sqlite / python）
在 **5 个目标平台**（linux / windows / macos / android / ios）上编译为**静态库**，
并发布为按平台区分、按库分开的 GitHub Release 产物（`include/` + `lib/`）。

APP 仓库（如 `Flutter_FileManager`）**不维护第三方库的跨平台编译逻辑**，
只从本仓库 Release 下载对应平台的产物使用（或直接 vendor 进 APP 工程）。

---

## 1. 设计原则

- **按平台组织、完全自包含**：目录以平台为顶层维度，每个
  `dependencies/<platform>/build.sh` 不依赖任何共享脚本/其它平台，单独即可编译该平台全部库。
- **构建逻辑复用已验证脚本**：各库编译函数照抄自 per-tool 已验证脚本，
  保证跨平台一致性，仅做平台编排（工具链 env）与产物合并。
- **平台配置集中在 workflow**：runner / 工具链 / ARCH 在
  `.github/workflows/build_platforms.yml` 对应平台 Job。
- **产物按平台区分、按库分开**：每个平台一个 GitHub Release，内含各库独立的 tarball。

---

## 2. 目录结构

```text
Flutter_CrossPlatformDependency/
├── dependencies/
│   ├── linux/   build.sh     # Linux x86_64
│   ├── windows/ build.sh     # Windows x86_64（MSYS2/MinGW64）
│   ├── macos/   build.sh     # macOS arm64
│   ├── android/ build.sh     # Android arm64-v8a（NDK 交叉）
│   └── ios/     build.sh     # iOS arm64
└── .github/workflows/
    └── build_platforms.yml   # 5 个平台 Job + release Job
```

### 每个平台 build.sh 结构

自包含脚本，包含以下段落：

| 段落 | 内容 |
|------|------|
| 环境 | `PLATFORM` / `ARCH` / `ARCH_DIR` / 工具链（CC/AR/SYSROOT 等） |
| 通用函数 | `dl_extract`（下载解压，含 Windows cygpath 处理）、`platform_cc/ar/jobs` 等 |
| 各库构建 | `build_ffmpeg` / `build_miniz` / `build_stb_image` / `build_sqlite` / `build_python` |
| 合并 | `stage_platform` 把各库 include/lib 合并为该平台统一产物 |

### 各平台编译的 5 个库

| 库 | 构建方式 | 产物 |
|----|---------|------|
| ffmpeg | autoconf（按平台 target-os，交叉加 `--enable-cross-compile`） | `libavformat.a` `libavcodec.a` `libavutil.a` `libswscale.a` `libswresample.a` |
| miniz | 直接编译 amalgamation | `libminiz.a` |
| stb_image | 直接编译 | `libstb_image.a` |
| sqlite | 直接编译 sqlite3.c | `libsqlite3.a` |
| python | linux/macos autoconf（原生，已验证）；windows 官方 embeddable；android 交叉、ios Apple-support（best-effort，交叉编译较难） | `libpython3.12.a` / embeddable / `.xcframework` |

> **python**：linux/macos/windows 真实编译；**android/ios 交叉编译 CPython 较难**
> （configure 无法运行目标二进制），为 best-effort——失败会明确报错并跳过该库，**不影响**
> ffmpeg/miniz/stb_image/sqlite 四个核心库及 linux/macos/windows 的 python。

---

## 3. 新增一个库（流程）

由于采用「按平台自包含」结构，新增一个库 = 在每个需要它的平台 `build.sh`
里加入该库的构建函数 + 合并，并（可选）加入 workflow 的打包/发布。

### 步骤 1：编写构建函数（照抄成熟模式）

参考现有 `build_miniz`/`build_sqlite`（直接编译）或 `build_ffmpeg`（autoconf）：

```bash
# 例：新增库 build_foo（直接编译）
build_foo() {
  local DEP_SRC_DIR=foo-1.0
  dl_extract foo "https://.../foo-1.0.tar.gz" "$DEP_SRC_DIR" "foo.tar.gz"   # 下载
  local cc; cc="$(platform_cc)"
  local inst="${STAGE_ROOT}/foo-inst"; rm -rf "$inst"; mkdir -p "$inst/include" "$inst/lib"
  local bd="${SRC_ROOT}/foo/build"; rm -rf "$bd"; mkdir -p "$bd"
  "${cc}" -O2 -fPIC -c "${SRC_ROOT}/foo/${DEP_SRC_DIR}/foo.c" -o "$bd/foo.o"
  $(platform_ar) rcs "$inst/lib/libfoo.a" "$bd/foo.o"                       # 归档
  cp "${SRC_ROOT}/foo/${DEP_SRC_DIR}/foo.h" "$inst/include/"                # 头文件
  # 输出到统一 stage
  stage_lib foo
  cp -a "$inst/include" "${STAGE_ROOT}/foo/${PLATFORM}/${ARCH_DIR}/include"
  cp -a "$inst/lib" "${STAGE_ROOT}/foo/${PLATFORM}/${ARCH_DIR}/lib"
  echo "[foo] 完成"
}
```

要点：
- **下载**用 `dl_extract <dep> <url> <src_dir> <tarball>`（已处理 Windows 路径）。
- **编译/归档**用 `platform_cc` / `platform_ar`（跨平台）。
- **产物**输出到 `${STAGE_ROOT}/<lib>/<PLATFORM>/<ARCH_DIR>/{include,lib}`。

### 步骤 2：在各平台调用并合并

在 `dependencies/<platform>/build.sh` 底部：

```bash
build_ffmpeg; build_miniz; build_stb_image; build_sqlite; build_python; build_foo   # 加 build_foo
stage_platform
```

`stage_platform` 已会自动合并 `foo` 的产物（因为它遍历固定列表，需把 `foo` 加入其 `for dep in ...` 循环）。

### 步骤 3：workflow 打包与发布

在 `build_platforms.yml` 的 `env.LIBS` 加入 `foo`，各平台 Package 步骤会自动
打出 `<platform>-foo.tar.gz`，release Job 会把它并入该平台的 Release。

---

## 4. 产物结构

每个平台一个 GitHub Release（tag = `linux` / `windows` / `macos` / `android` / `ios`），
内含该平台**各库独立的 tarball**：

```text
linux Release:
  linux-ffmpeg.tar.gz    linux-miniz.tar.gz    linux-stb_image.tar.gz
  linux-sqlite.tar.gz    linux-python.tar.gz
windows Release:
  windows-ffmpeg.tar.gz  windows-sqlite.tar.gz ...
macos / android / ios 同理
```

每个 `<platform>-<lib>.tar.gz` 解压后为该库的 `include/` + `lib/`。

架构：linux x86_64 / windows x86_64 / macos arm64 / android arm64-v8a / ios arm64。

---

## 5. 触发 CI

push `build-*` tag 或手动触发 `Build All Platforms`：

```bash
git tag build-1.0.0
git push origin build-1.0.0
```

修改后重新打 tag 到最新 commit 再推送即可触发重建（各平台 Release 会被覆盖更新）。

---

## 6. APP 端如何消费

APP 下载对应平台 Release 里的各库 tarball：

```text
https://github.com/naipingzai/Flutter_CrossPlatformDependency/releases/download/<platform>/<platform>-<lib>.tar.gz
# 例：https://.../releases/download/windows/windows-ffmpeg.tar.gz
```

解压得该库的 `include/` + `lib/`，加入头文件路径并链接静态库；
也可把各平台各库合并后直接 vendor 进 APP 工程。
