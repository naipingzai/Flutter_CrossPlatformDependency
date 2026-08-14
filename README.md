# Flutter_CrossPlatformDependency

> 第三方原生 C/C++ 库的**跨平台静态编译**仓库。
> 只负责「获取源码 → 编译 → 发布产物」，不参与任何 APP 业务逻辑。

APP 仓库（如 `Flutter_FileManager`）**不维护第三方库的跨平台编译逻辑**，
只从本仓库的 GitHub Release 下载对应平台的 `include/` 与 `lib/` 使用。

---

## 1. 目标与原则

- **平台配置集中在 workflow（YAML）**，按平台清晰区分（runner / 工具链 / ARCH / 编译参数）。
- **构建逻辑复用通用引擎** `scripts/common.sh`，脚本内不做平台业务分支。
- **每个依赖一个目录** `dependencies/<dep>/`，新增依赖遵循统一规范，保证结构一致、可维护、可扩展。
- **统一产物结构**，便于 APP 端按平台自动消费。

---

## 2. 目录结构

```text
Flutter_CrossPlatformDependency/
├── scripts/
│   └── common.sh                通用构建引擎（下载 / configure / make / 整理产物）
│
├── dependencies/
│   └── <dep>/                   每个第三方库一个目录（规范结构见 §4）
│       ├── build.sh             依赖构建入口（复用 common.sh）
│       └── dependency.yaml      依赖配置（版本 / 平台 / 产物结构）
│
├── toolchains/                  （预留）CMake 型依赖的跨编译工具链
│   ├── android.cmake
│   └── ios.cmake
│
└── .github/workflows/
    ├── build_<dep>.yml          平台矩阵 + 发布 Release（规范结构见 §5）
    └── ...
```

---

## 2.1 当前已支持依赖

| 依赖 | 版本 | 产物 tag | 构建工作流 |
|------|------|----------|-----------|
| FFmpeg | n7.1 | `ffmpeg-n7.1` | `build_ffmpeg.yml` |

新增依赖后在此登记（对应 §4 步骤 6）。

---

## 3. 通用引擎 `scripts/common.sh`

`common.sh` 提供对 `configure + make` 型（autoconf 型）第三方库的通用构建能力。
**平台无业务分支**，唯一的平台分支点是 `PLATFORM` → `target-os / 交叉编译开关`。

### 3.1 依赖侧需设置的变量（在 `dependencies/<dep>/build.sh` 中）

| 变量 | 必填 | 说明 |
|------|:----:|------|
| `DEP_NAME` | ✅ | 依赖名，决定产物目录名（如 `ffmpeg`） |
| `DEP_URL` | ✅ | 源码归档 URL |
| `DEP_TARBALL` | ✅ | 归档文件名（`.tar.xz` / `.tar.gz`） |
| `DEP_SRC_DIR` | ✅ | 解压后的源码目录名 |
| `DEP_STATIC` | 否 | `1`=静态库（默认） `0`=动态库 |
| `CONFIGURE_FLAGS` | 否 | 依赖自身的 configure 参数 |
| `DEP_SOURCE_ROOT` | 否 | 源码下载目录（默认 `$RUNNER_TEMP/<dep>-src`） |
| `DEP_STAGE_ROOT` | 否 | 产物暂存目录（默认 `$RUNNER_TEMP/<dep>-stage`） |

### 3.2 平台侧注入的变量（由 workflow 的每个平台 Job 设置）

| 变量 | 说明 |
|------|------|
| `PLATFORM` | `linux` / `windows` / `macos` / `android` / `ios` |
| `ARCH` | 架构：`x86_64` / `arm64` / `aarch64` ... |
| `ARCH_DIR` | 产物子目录名（Android ABI 名 / macOS arch，默认 = `ARCH`） |
| `CC` / `CXX` | 编译器（交叉编译时指定） |
| `SYSROOT` | 系统根目录（交叉编译时指定） |
| `CROSS_PREFIX` | 交叉工具链前缀（可选） |
| `EXTRA_CFLAGS` | 额外编译参数（如 `-DANDROID -fPIC`） |
| `EXTRA_LDFLAGS` | 额外链接参数（注意需带 `-L` 前缀） |
| `PLAT_OUT` | 产物平台目录名（默认 = `PLATFORM`） |

### 3.3 提供的函数

| 函数 | 作用 |
|------|------|
| `dep_fetch_source` | 下载并解压源码（已存在则跳过；兼容 `.tar.xz` / `.tar.gz`） |
| `dep_build` | 组装 configure 参数 → configure → make → make install |
| `dep_stage_output` | 把 `include/`、`lib/` 整理到统一产物结构 |
| `dep_make_flags` | 生成并行编译参数 `-j<N>` |

`dep_build` 产出的目标 OS 映射：`linux→linux`、`windows→mingw32`、`macos→darwin`、`android→android`、`ios→darwin`；`macos/android/ios` 自动开启交叉编译；`ios` 自动加 `--disable-asm`。

---

## 4. 新增一个开源库的规范流程

> 以下为**新增依赖的统一标准流程**。严格照做即可让新库与现有实现保持一致。

### 步骤 1：创建依赖目录

```bash
mkdir -p dependencies/<dep>
```

### 步骤 2：编写 `dependencies/<dep>/build.sh`

复制 `dependencies/ffmpeg/build.sh`，只修改三处：

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/common.sh"

# ① 依赖常量
export DEP_NAME="<dep>"
DEP_VERSION="<x.y.z>"
export DEP_TARBALL="<dep>-${DEP_VERSION}.tar.xz"
export DEP_URL="https://.../${DEP_TARBALL}"
export DEP_SRC_DIR="<dep>-${DEP_VERSION}"
export DEP_STATIC="1"

# ② 源码/stage 目录（保持默认）
export DEP_SOURCE_ROOT="${DEP_SOURCE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-src}"
export DEP_STAGE_ROOT="${DEP_STAGE_ROOT:-${RUNNER_TEMP:-/tmp}/${DEP_NAME}-stage}"
export DEP_OUTPUT_DIR="${DEP_NAME}"

# ③ 依赖自身的 configure 参数（可选）
export CONFIGURE_FLAGS="<--xxx --yyy ...>"

# 执行（三行固定）
dep_fetch_source
dep_build
dep_stage_output
```

**约束**：只修改源码常量与 `CONFIGURE_FLAGS`，**不要**在脚本里写平台分支。

### 步骤 3：编写 `dependencies/<dep>/dependency.yaml`

```yaml
name: <dep>
version: "<x.y.z>"

source:
  url: https://.../<dep>-<x.y.z>.tar.xz
  sha256: ""               # 可选，留空不校验

build:
  type: static             # 只输出静态库（.a / .lib）
  engine: autoconf         # configure + make（复用 scripts/common.sh）
  output:
    include: include/
    lib: lib/

platforms:
  windows: { enabled: true, arch: [x86_64] }
  linux:   { enabled: true, arch: [x86_64] }
  macos:   { enabled: true, arch: [arm64] }
  android: { enabled: true, abi: [arm64-v8a], min_sdk: 21 }
  ios:     { enabled: true, arch: [arm64] }
```

### 步骤 4：编写 `.github/workflows/build_<dep>.yml`

复制 `build_ffmpeg.yml`，按以下模板套用（各平台 Job 结构固定）：

```yaml
name: Build <Dep> Static Libs

on:
  workflow_dispatch:
  push:
    tags: ['<dep>-*']          # 触发 tag 按依赖命名

permissions:
  contents: write

env:
  RELEASE_TAG: "<dep>-<version>"   # 如 ffmpeg-n7.1

jobs:
  # ---- 每个平台一个 Job，结构：环境变量 → 装工具链 → Build → Package → upload ----
  linux:
    runs-on: ubuntu-24.04
    env: { PLATFORM: linux, ARCH: x86_64, ARCH_DIR: x86_64 }
    steps:
      - uses: actions/checkout@v4
      - name: Install deps
        run: sudo apt-get update && sudo apt-get install -y make gcc g++ xz-utils curl
      - name: Build
        run: bash dependencies/<dep>/build.sh
      - name: Package
        run: |
          cd "${RUNNER_TEMP}/<dep>-stage/<dep>"
          tar -czf "${RUNNER_TEMP}/<dep>-linux.tar.gz" linux
      - uses: actions/upload-artifact@v4
        with:
          name: <dep>-linux
          path: ${{ runner.temp }}/<dep>-linux.tar.gz

  # Windows: 需 msys2 + cygpath；macOS/iOS: xcrun 在 run 内求值；
  # Android: setup-ndk 注入 CC/CXX/SYSROOT/EXTRA_LDFLAGS(-L)
  # ...（其余平台同上，按 ffmpeg 示例逐平台配置）

  release:
    runs-on: ubuntu-24.04
    needs: [linux, windows, macos, android, ios]
    if: always()
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with: { path: release-assets, merge-multiple: true }
      - name: Create/Update Release
        env: { GH_TOKEN: ${{ github.token }}, RELEASE_TAG: ${{ env.RELEASE_TAG }} }
        run: |
          gh release delete "${RELEASE_TAG}" --yes --cleanup-tag 2>/dev/null || true
          gh release create "${RELEASE_TAG}" \
            --title "<Dep> ${RELEASE_TAG}" \
            --notes "<Dep> <版本> 跨平台静态库" \
            $(find release-assets -type f -name '*.tar.gz')
```

### 步骤 5：平台 Job 模板速查（照抄即用）

| 平台 | runner | 关键设置 |
|------|--------|----------|
| **Linux** | `ubuntu-24.04` | apt 装 `make gcc g++ xz-utils curl`；Build 直接 `bash .../build.sh` |
| **Windows** | `windows-latest` + `msys2/setup-msys2` | `msystem: MINGW64`；`defaults.run.shell: msys2 {0}`；Package 用 `cygpath` 转路径 |
| **macOS** | `macos-14` | 在 `run:` 内 `export CC/SYSROOT=$(xcrun ...)`（勿放 `env:`，`$()` 在 env 里按字面量） |
| **Android** | `ubuntu-24.04` + `nttld/setup-ndk` | 用 `${{ steps.ndk.outputs.ndk-path }}` 拼 `CC/CXX/SYSROOT`；`EXTRA_LDFLAGS` 需带 `-L`；`EXTRA_CFLAGS=-DANDROID -fPIC` |
| **iOS** | `macos-14` | `run:` 内 `export CC/SYSROOT=$(xcrun --sdk iphoneos ...)` |

### 步骤 6：更新 `README.md`

- 在「支持的依赖」表中登记新库、版本、产物 tag。
- 保持本规范文档与当前实现一致。

### 步骤 7：触发并验证

- 手动：Actions → `Build <Dep> Static Libs` → Run workflow。
- 或推送 tag：`git tag <dep>-<version> && git push origin <dep>-<version>`。
- 验证 Release 已生成 `<dep>-<plat>.tar.gz`，且解压结构为 `<dep>/<plat>/<arch>/{include,lib}`。

---

## 5. 产物统一结构

```text
<dep>/<plat>/<arch>/
├── include/              头文件（所有平台一致）
└── lib/                  静态库（平台相关）
```

| `<plat>` | `<arch>` |
|----------|----------|
| `windows` | `x86_64` |
| `linux` | `x86_64` |
| `macos` | `arm64` |
| `android` | `arm64-v8a` |
| `ios` | `arm64` |

每个平台打包为 `ffmpeg-<plat>.tar.gz` 上传；`release` Job 汇总后发布到对应 tag 的 GitHub Release。

---

## 6. APP 端如何消费

APP 的 CMake 在配置阶段按当前平台/ABI，从本仓库 Release 下载对应 tarball：

```cmake
# 例：FFmpeg
https://github.com/naipingzai/Flutter_CrossPlatformDependency/releases/download/ffmpeg-n7.1/ffmpeg-<plat>.tar.gz
```

解压后得到 `ffmpeg/<plat>/<arch>/{include,lib}`，APP 将 `include/` 加入头文件路径，
将 `lib/` 中的静态库链接进 Native 库即可。APP 不参与任何第三方库编译。

---

## 7. 平台构建已知要点 / 注意事项

1. **Windows 必须是 MSYS2/MinGW64 原生构建**，不要加 `--cross-prefix`（会找不到 `ar`）。
2. **macOS/iOS 的 `CC`/`SYSROOT` 用 `$(xcrun ...)` 时必须在 `run:` 内 `export`**，放在 `env:` 中会按字面量处理导致编译失败。
3. **Android `EXTRA_LDFLAGS` 必须带 `-L` 前缀**（裸目录会被当链接参数导致失败）。
4. **Android 只构建 64 位 `arm64-v8a`**；32 位 x86 会触发 FFmpeg 内联汇编寄存器不足问题。
5. **macOS 只构建 `arm64`**（Apple Silicon）：arm64 runner 上交叉编 x86_64 会触发 FFmpeg x86 内联汇编与 clang 的约束错误。
6. **产物 stage 目录**：构建脚本输出到 `$RUNNER_TEMP/<dep>-stage/<dep>/<plat>/<arch>`，workflow 的 Package 步骤据此打包。

---

## 8. 触发构建

- **手动**：仓库 Actions 页 → 选择对应 workflow → **Run workflow**。
- **tag 推送**：推送形如 `<dep>-*` 的 tag（如 `ffmpeg-n7.1`）自动触发对应 workflow。
