# Flutter_CrossPlatformDependency

> 第三方 C/C++ 库的**跨平台编译**仓库。
> 同时编译**静态库（.a）**和**动态库（.so/.dylib/.dll）**，iOS 仅静态库。
> 不参与任何 APP 业务逻辑，只负责「获取源码 → 编译 → 发布产物」。

---

## 编译的库

| 库 | 构建方式 | 静态库 | 动态库 |
|----|---------|--------|--------|
| ffmpeg 7.1 | autoconf（`--enable-static --enable-shared`） | `libavformat.a` `libavcodec.a` `libavutil.a` `libswscale.a` `libswresample.a` | `libavformat.so/.dylib/.dll` 等 |
| miniz 2.2.0 | 直接编译 amalgamation（-fPIC） | `libminiz.a` | `libminiz.so/.dylib/.dll` |
| stb_image | 直接编译（-fPIC） | `libstb_image.a` | `libstb_image.so/.dylib/.dll` |
| sqlite 3.46 | 直接编译 sqlite3.c（-fPIC） | `libsqlite3.a` | `libsqlite3.so/.dylib/.dll` |
| python 3.12 | autoconf 或 embed 包 | `libpython3.12.a` | 仅静态 |

> **python**：linux/macos/windows 原生编译；android 交叉编译；ios 不编译（best-effort）。
> python 失败不影响其他四个库。

---

## 支持平台

| 平台 | 架构 | 动态库扩展名 | 需要 PIC | 备注 |
|------|------|:---:|:---:|------|
| Linux | x86_64 | `.so` | 是 | GitHub Actions `ubuntu-24.04` |
| Windows | x86_64 | `.dll` | 否 | GitHub Actions `windows-latest` + MSYS2/MinGW64 |
| macOS | arm64 | `.dylib` | 是 | GitHub Actions `macos-14` |
| Android | arm64-v8a | `.so` | **强制** | NDK r27c 交叉编译，workflow 注入 `-fPIC` |
| iOS | arm64 | — | 否 | **仅静态库**（App Store 禁止第三方动态库） |

---

## 目录结构

```text
Flutter_CrossPlatformDependency/
├── dependencies/
│   ├── linux_build.sh      # Linux x86_64 全量构建脚本
│   ├── windows_build.sh    # Windows x86_64 全量构建脚本
│   ├── macos_build.sh      # macOS arm64 全量构建脚本
│   ├── android_build.sh    # Android arm64-v8a 全量构建脚本
│   └── ios_build.sh        # iOS arm64 全量构建脚本
├── .github/workflows/
│   └── build_platforms.yml # CI：5 个平台 Job + Release Job
└── README.md
```

每个 `*_build.sh` 是**完全自包含**的，不依赖任何共享脚本。包含：
- 环境设置（PLATFORM/ARCH/CC/AR/SYSROOT 等）
- 通用函数（`dl_extract`/`platform_cc`/`platform_ar` 等）
- 5 个库的构建函数（`build_ffmpeg`/`build_miniz` 等）
- 合并（`stage_platform`）

---

## CI 流程

push `build-*` tag 或手动触发 `Build All Platforms`：

```bash
git tag build-xxx
git push origin build-xxx
```

每个平台 Job：
1. 拉取源码 + 安装依赖
2. 运行 `dependencies/<platform>_build.sh`
3. 将产物按库独立打包为 `linux-ffmpeg.tar.gz` 等
4. 上传 artifact

Release Job：
- 汇集所有平台产物，发布为**单一 GitHub Release**（tag = `latest`）
- 附带 Markdown 下载表格（行=库，列=平台）

---

## 产物结构

每个 tarball 解压后包含 `include/` + `lib/`：

```text
linux-ffmpeg.tar.gz
  ├── include/    # 头文件
  └── lib/
      ├── libavcodec.a      # 静态库
      ├── libavcodec.so      # 动态库
      └── ...
```

---

## APP 端消费方式

从 `latest` Release 下载对应平台+库的压缩包：

```
https://github.com/naipingzai/Flutter_CrossPlatformDependency/releases/download/latest/<platform>-<lib>.tar.gz
```

示例：
- `linux-ffmpeg.tar.gz`
- `windows-sqlite.tar.gz`
- `android-ffmpeg.tar.gz`
- `macos-miniz.tar.gz`
- `ios-stb_image.tar.gz`

### 静态库 vs 动态库选择

| 场景 | 推荐 | 原因 |
|------|------|------|
| iOS App Store 发布 | 静态库 `.a` | Apple 禁止运行时加载第三方动态库 |
| Android APP | 静态库打包进 `.so` | 通过 `DynamicLibrary.open('libfileops.so')` 加载 |
| Linux/Windows/macOS 桌面 | 静态库 `.a` 或动态库 | 按需选择 |
| 开发/测试 | 动态库 | 修改后无需重新链接整个程序 |

---

## 新增一个库

1. 在 `dependencies/<platform>_build.sh` 中添加 `build_mylib()` 函数
2. 在脚本底部的构建列表中加入 `build_mylib`
3. 在 `.github/workflows/build_platforms.yml` 的 `DEP_LIBS` 中加入 `mylib`

参考现有 `build_miniz`（直接编译）或 `build_ffmpeg`（autoconf）。

---

## Android PIC 说明

Android 通过 `DynamicLibrary.open('libfileops.so')` 加载原生代码，
共享库在 ARM64 上强制要求所有代码为位置无关（PIC）。

若静态库缺 `-fPIC`，链接时报：
```
relocation R_AARCH64_ADR_PREL_PG_HI21 cannot be used against symbol ...
recompile with -fPIC
```

本仓库通过 workflow 注入 `EXTRA_CFLAGS="-DANDROID -fPIC"` 和 FFmpeg 的 `--enable-pic` 保证。
