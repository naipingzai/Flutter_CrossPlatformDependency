# Flutter_CrossPlatformDependency

> 第三方原生 C/C++ 库的**跨平台静态编译**仓库。
> 只负责「获取源码 → 编译 → 发布产物」，不参与任何 APP 业务逻辑。

APP 仓库（如 `Flutter_FileManager`）**不维护第三方库的跨平台编译逻辑**，
只从本仓库的 GitHub Release 下载对应平台的 `include/` 与 `lib/` 使用。

---

## 1. 设计原则

- **按平台组织**：目录以平台为顶层维度，每个平台目录**完全自包含**，
  编译该平台所需的全部库（ffmpeg / miniz / stb_image / sqlite / python）。
- **构建逻辑复用已验证脚本**：各库的编译函数照抄自 per-tool 已验证脚本，
  仅做平台编排（工具链 env）与产物合并。
- **平台配置集中在 workflow**：runner / 工具链 / ARCH 在
  `.github/workflows/build_platforms.yml` 对应平台 Job。
- **产物按平台区分**：每个平台一个 GitHub Release（linux/windows/macos/android/ios）。

---

## 2. 目录结构

```text
Flutter_CrossPlatformDependency/
├── dependencies/
│   ├── linux/   build.sh     # Linux x86_64：ffmpeg/miniz/stb_image/sqlite/python
│   ├── windows/ build.sh     # Windows x86_64（MSYS2/MinGW64）
│   ├── macos/   build.sh     # macOS arm64
│   ├── android/ build.sh     # Android arm64-v8a（NDK 交叉）
│   └── ios/     build.sh     # iOS arm64
└── .github/workflows/
    └── build_platforms.yml   # 5 个平台 Job + release Job（按平台发布）
```

每个 `dependencies/<platform>/build.sh` 是自包含脚本，包含 5 个库的构建函数：

| 库 | 构建方式 |
|----|---------|
| ffmpeg | autoconf（按平台 target-os，交叉加 --enable-cross-compile） |
| miniz | 直接编译 amalgamation → libminiz.a |
| stb_image | 直接编译 → libstb_image.a |
| sqlite | 直接编译 sqlite3.c → libsqlite3.a |
| python | linux/macos autoconf；windows 官方 embeddable；android 交叉(best-effort)；ios Apple-support(best-effort) |

> **python** 为 best-effort：构建失败仅明确告警、跳过合并，**不影响**
> ffmpeg/miniz/stb_image/sqlite 四个核心库的产出。

---

## 3. 产物

每个平台合并为 `include/` + `lib/`，打包 `<platform>.tar.gz`，发布到以平台名命名的
GitHub Release（`linux` / `windows` / `macos` / `android` / `ios`）：

```text
<platform>.tar.gz -> { include, lib }
include/  各库头文件（libav*/、sqlite3.h、stb_image.h、miniz.h、Python.h...）
lib/      各库静态库（libav*.a、libsqlite3.a、libstb_image.a、libminiz.a、libpython3.12.a...）
```

架构：linux x86_64 / windows x86_64 / macos arm64 / android arm64-v8a / ios arm64。

---

## 4. 触发 CI

push `build-*` tag 或手动触发 `Build All Platforms`：

```bash
git tag build-1.0.0
git push origin build-1.0.0
```

修改后重新打 tag 到最新 commit 再推送即可触发重建。

---

## 5. APP 端如何消费

APP 下载对应平台的 Release：

```text
https://github.com/naipingzai/Flutter_CrossPlatformDependency/releases/download/<platform>/<platform>.tar.gz
```

解压得 `include/` + `lib/`，加入头文件路径并链接静态库；也可直接 vendor 进 APP 工程。
