# Flutter_CrossPlatformDependency

> 第三方原生 C/C++ 库的**跨平台静态编译**仓库。
> 只负责「获取源码 → 编译 → 发布产物」，不参与任何 APP 业务逻辑。

APP 仓库（如 `Flutter_FileManager`）**不维护第三方库的跨平台编译逻辑**，
只从本仓库的 GitHub Release 下载对应平台的 `include/` 与 `lib/` 使用。

---

## 1. 设计原则

- **每个库完全独立、零耦合**：每个依赖自成目录，内含自包含的 `build.sh`，不依赖仓库内任何其他脚本。新增/修改某个库**不会影响其他库**。
- **平台配置集中在 workflow（YAML）**：runner / 工具链 / ARCH / 编译参数都在 `.github/workflows/build_<dep>.yml`。
- **编译规则在 `build.sh` 内清晰标注**：下载、平台、configure、产物整理分别成段。
- **目录尽量扁平、简单**：每个库 = `build.sh` + `dependency.yaml`，外加仓库级 workflow 一个文件。

---

## 2. 目录结构

```text
Flutter_CrossPlatformDependency/
├── dependencies/
│   └── <dep>/                        # 每个第三方库一个独立目录（见 §3 规范）
│       ├── build.sh                  # 自包含构建脚本（内含标注的编译规则）
│       └── dependency.yaml           # 依赖配置（版本 / 平台 / 产物结构）
│
└── .github/workflows/
    └── build_<dep>.yml               # 该库的平台矩阵 + 发布 Release（每个库一份）
```

> 库之间没有共享脚本。若某库是 CMake 型依赖，其工具链配置放在**该库自己的目录**内，不放在顶层。

---

## 3. 新增一个开源库的规范流程

每个库 = **1 个目录 + 1 个 workflow 文件**，完全独立。按以下步骤做即可。

### 步骤 1：创建依赖目录，复制自包含模板

```bash
cp -r dependencies/ffmpeg dependencies/<dep>
```

### 步骤 2：改写 `dependencies/<dep>/build.sh`

`build.sh` 是**自包含脚本**，结构固定，规则分段清晰：

| 段落 | 内容 | 需修改？ |
|------|------|:--------:|
| **规则 A 依赖常量** | 库名、版本、源码 URL、configure 参数 | ✅ 必须 |
| **规则 B 平台规则** | 目标 OS 映射、交叉编译开关 | ⚠️ 一般不改 |
| **规则 C 下载规则** | 下载并解压源码 | 不改 |
| **规则 D 构建规则** | 组装 configure → make → install | ⚠️ 视库而定 |
| **规则 E 产物整理** | 输出到统一结构 | 不改 |

**规则 A 只需改这几处**：

```bash
DEP_NAME="<dep>"                                    # 库名（决定产物目录）
DEP_VERSION="<x.y.z>"
DEP_TARBALL="<dep>-${DEP_VERSION}.tar.xz"
DEP_URL="https://.../${DEP_TARBALL}"
DEP_SRC_DIR="<dep>-${DEP_VERSION}"

DEP_CONFIGURE_FLAGS="<--xxx --yyy ...>"             # 本库自身的 configure 参数
```

> 若新库的 configure/构建方式差异较大，只需在「规则 D」内调整，不影响其他库。

### 步骤 3：改写 `dependencies/<dep>/dependency.yaml`

```yaml
name: <dep>
version: "<x.y.z>"

source:
  url: https://.../<dep>-<x.y.z>.tar.xz
  sha256: ""

build:
  type: static             # 静态库（.a / .lib）
  engine: autoconf         # ./configure + make
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

### 步骤 4：改写 `.github/workflows/build_<dep>.yml`

复制 `build_ffmpeg.yml`，改四处：

| 位置 | 改法 |
|------|------|
| `name` | `Build <Dep> Static Libs` |
| `on.push.tags` | `<dep>-*` |
| `env.RELEASE_TAG` | `<dep>-<version>`（如 `ffmpeg-n7.1`） |
| 每个 Job 的 `bash dependencies/...` | 指向 `dependencies/<dep>/build.sh` |

各平台 Job 的**环境变量注入规则**（照抄即用，见下方 §4）。

### 步骤 5：登记并触发验证

- 在 `README.md` §8 登记新库。
- 按 §9 推送 tag（或手动触发）跑通 CI，并验证 Release 产物。

---

## 4. 平台 Job 模板速查（每个库的 workflow 都相同结构）

| 平台 | runner | 关键规则 |
|------|--------|----------|
| **Linux** | `ubuntu-24.04` | apt 装 `make gcc g++ xz-utils curl`；`env: {PLATFORM: linux, ARCH: x86_64, ARCH_DIR: x86_64}` |
| **Windows** | `windows-latest` + `msys2/setup-msys2` | `msystem: MINGW64` + `defaults.run.shell: msys2 {0}`；Package 用 `cygpath` 转路径；装 `mingw-w64-x86_64-gcc` |
| **macOS** | `macos-14` | 在 `run:` 内 `export CC/SYSROOT=$(xcrun --sdk macosx ...)`（**勿放 `env:`**，`$()` 在 env 里按字面量） |
| **Android** | `ubuntu-24.04` + `nttld/setup-ndk` | 用 `${{ steps.ndk.outputs.ndk-path }}` 拼 `CC/CXX/SYSROOT`；`EXTRA_CFLAGS=-DANDROID -fPIC`；`EXTRA_LDFLAGS` **必须带 `-L`** |
| **iOS** | `macos-14` | 在 `run:` 内 `export CC/SYSROOT=$(xcrun --sdk iphoneos ...)` |

每个 Job 结构固定：**装工具链 → `bash dependencies/<dep>/build.sh` → 打包 → upload**。

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

每个平台打包为 `<dep>-<plat>.tar.gz`，`release` Job 汇总后发布到对应 tag 的 GitHub Release。

---

## 6. 平台构建已知要点

1. **Windows 用 MSYS2/MinGW64 原生构建**，不要加 `--cross-prefix`（会找不到 `ar`）。
2. **macOS/iOS 的 `CC`/`SYSROOT`**：`$(xcrun ...)` 必须在 `run:` 内 `export`。
3. **Android `EXTRA_LDFLAGS` 必须带 `-L`**（裸目录当链接参数会失败）。
4. **只构建 64 位**：Android `arm64-v8a`；32 位 x86 会触发内联汇编寄存器不足。
5. **macOS 只构建 `arm64`**（Apple Silicon）；arm64 runner 上交叉编 x86_64 有 FFmpeg 汇编问题。

---

## 7. APP 端如何消费

APP 的 CMake 在配置阶段按当前平台/ABI，从本仓库 Release 下载对应 tarball：

```text
https://github.com/naipingzai/Flutter_CrossPlatformDependency/releases/download/<dep>-<version>/<dep>-<plat>.tar.gz
```

解压得 `<dep>/<plat>/<arch>/{include,lib}`，APP 把 `include/` 加入头文件路径、把 `lib/` 静态库链接进 Native 库即可。APP 不参与任何第三方库编译。

---

## 8. 当前已支持依赖

| 依赖 | 版本 | 产物 tag | 工作流 |
|------|------|----------|--------|
| FFmpeg | n7.1 | `ffmpeg-n7.1` | `build_ffmpeg.yml` |
| Python | 3.12.7 | `python-3.12.7` | `build_python.yml` |

> **Python 特别说明**：产物为**可嵌入解释器**，结构为
> `python/<plat>/<arch>/{include,lib}`，其中 `lib/` 内含
> `libpython3.x.a`（静态解释器）与 `python3.x/`（标准库）。
> Linux / macOS 为原生构建（已在本机验证可嵌入：C 程序静态链接
> `libpython3.12.a` 并成功运行 Python）。
> Android / iOS / Windows(MinGW) 为交叉编译，需要 `--host` 三元组与
> 同版本的 `BUILD_PYTHON`（主机 python），属于进阶能力，可能需按 CI 结果迭代。

## 9. 触发 CI 与推送流程

> 每个库的 workflow 通过推送形如 `<dep>-*` 的 **tag** 自动触发（也支持手动）。

### 9.1 tag 命名规范

| 依赖 | 产物 tag |
|------|----------|
| FFmpeg | `ffmpeg-n7.1` |
| Python | `python-3.12.7` |

### 9.2 首次触发（打 tag 并推送）

```bash
# 在仓库根目录
git tag <dep>-<version>          # 例：git tag python-3.12.7
git push origin <dep>-<version>  # 例：git push origin python-3.12.7
```

推送后，对应 `.github/workflows/build_<dep>.yml` 自动运行：
5 个平台 Job（linux/windows/macos/android/ios）→ `release` Job 汇总并发布到
该 tag 的 GitHub Release（产物为 `<dep>-<plat>.tar.gz`）。

### 9.3 修改后重新构建（删除并重建 tag）

若改了代码想重跑，删除旧 tag 再打新 tag 推送即可（release 会被覆盖更新）：

```bash
git push origin :refs/tags/<dep>-<version>   # 删除远端 tag
git tag -d <dep>-<version>                    # 删除本地 tag
git tag <dep>-<version>                       # 重新打 tag（指向最新 commit）
git push origin <dep>-<version>               # 触发 CI
```

> 注意：`git tag` 会固定在某次 commit。每次改动后都要重新打 tag 到最新 commit，
> 否则 CI 用的还是旧代码。

### 9.4 手动触发

Actions → 选择 `Build <Dep> Static Libs` → **Run workflow**。

### 9.5 查看结果与产物

1. **进度**：仓库 `Actions` 页查看各平台 Job 是否通过。
2. **Release**：构建全部通过后，`release` Job 把产物发布到对应 tag 的 Release
   （`Releases` → `<dep>-<version>`）。
3. **产物结构**：每个 `<dep>-<plat>.tar.gz` 解压后为 `<dep>/<plat>/<arch>/{include,lib}`。

### 9.6 消费 Release

APP 端按下述 URL 下载对应平台产物（见 §7）：

```text
https://github.com/naipingzai/Flutter_CrossPlatformDependency/releases/download/<dep>-<version>/<dep>-<plat>.tar.gz
```
