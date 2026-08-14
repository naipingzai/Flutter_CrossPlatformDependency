# dependencies/python

CPython（3.12.7）可嵌入解释器静态库的构建。

## 构建脚本与平台对应

CPython 在不同平台的构建方式差异很大，因此本依赖下有 **3 个构建脚本**：

| 脚本 | 平台 | 构建方式 |
|------|------|----------|
| `build.sh` | linux / macos / android | `./configure + make`（autoconf，静态 `libpython3.12.a`） |
| `build_windows.sh` | windows | 官方 **Windows embeddable 包** + 源码头文件 + `gendef/dlltool` 导入库 |
| `build_ios.sh` | ios | `pybee/Python-Apple-support`（官方认可的 iOS 构建，产出 `Python.xcframework`） |

> 说明：
> - **Windows**：CPython 官方用 MSVC/PCbuild（非 autoconf）；MinGW configure
>   会因盘符冒号破坏 Makefile，故改用官方 embeddable 包。
> - **iOS**：上游 CPython autoconf 不支持 iOS 交叉编译，改用 Python-Apple-support。

## 各平台产物

统一结构 `python/<plat>/<arch>/{include,lib}`：

| 平台 | 目录 | `lib/` 内容 | 链接方式 |
|------|------|------------|----------|
| linux | `linux/x86_64` | `libpython3.12.a` + `python3.12/`(stdlib) | 静态 `-lpython3.12` |
| macos | `macos/arm64` | `libpython3.12.a` + `python3.12/`(stdlib) | 静态 `-lpython3.12` |
| android | `android/arm64-v8a` | `libpython3.12.a` + `python3.12/`(stdlib) | 静态 `-lpython3.12` |
| windows | `windows/x86_64` | `python312.dll` + `libpython312.a`(导入库) + `python312.zip` + `*.pyd` | 链接 `-lpython312`，随程序带 DLL |
| ios | `ios/arm64` | `Python.xcframework`（内含静态运行时 + 标准库） | 链接 xcframework |

## 新增/升级版本

1. 修改 3 个脚本顶部的 `DEP_VERSION`（和 `DEP_VERSION` 相关 URL）。
2. 修改 `dependency.yaml` 的 `version`。
3. 按主仓库 README §9 推送 tag 触发 CI。
