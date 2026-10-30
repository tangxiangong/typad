# iPad 开发

在 `macos/TyPad.xcodeproj` 中选择 **TyPad-iPad** scheme；原来的 **TyPad** scheme 继续构建 macOS 应用。iPad Target 最低支持 iPadOS 17，仅包含 iPad 设备族。

```sh
# arm64 iPad 设备构建，不签名、不连接设备
bash ipad/build.sh
# arm64 模拟器构建，不启动模拟器
bash ipad/build.sh --simulator
```

真机运行或归档时，在 Xcode 的 TyPad-iPad Target 中配置自己的 Signing Team。命令行脚本默认禁用签名，仅用于构建验证。

## 功能与平台边界

- 使用系统文档浏览器新建、打开、保存 `.typ` 文档。
- 原生 UIKit 编辑器支持中文输入、撤销重做、系统查找及动态字体。
- 宽窗口并排显示源码和 PDF，窄窗口通过分段控件切换。
- 后台本地 Typst 编译、350 ms 防抖、错误诊断及 PDF 导出；编译失败保留上次成功预览，过期预览不能导出。
- 多个窗口共用串行编译队列，避免同时运行多个内存密集编译。原生编译运行中不能强制终止；关闭文档或编辑后的旧结果会被丢弃。
- 通过文档选项中的“允许资源文件夹…”授权文档所在文件夹后，编译器可读取同目录资源。授权在当前文档会话内使用，重新打开时需重新选择；云端资源需要已下载。

iPad 使用现有 `typad-ffi` 的快照编译接口，不启动 `typad-worker`，也没有 macOS 工作进程的崩溃隔离。当前 iPad 编译后端不支持 Typst 包导入；Tinymist 补全、快速帮助及 macOS 专用侧栏尚未移植。

## 构建组织

- `TyPad-iPad` → `TyPadCore-iPad` → `RustBindings-iPad`。
- 与 macOS 共享 `TypstDocument.swift`、图标、本地化资源和 Rust 核心。
- 生成的 Swift 模块名保持 `TyPadCore`，绑定输出按配置和平台分目录，设备与模拟器的静态库不混用。
- macOS arm64 构建后运行 `bash ci/check-ipad.sh`，在本机验证 iPad 编译模型的防抖、真实 PDF 输出、错误恢复和取消行为，不启动 GUI。
- `bash ci/check-macos.sh` 同时检查两个平台的 plist、scheme、脚本及 Swift 语法；平台类型检查和链接由对应 Xcode 构建完成。
