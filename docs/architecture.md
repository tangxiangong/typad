# 架构

TyPad 采用共享 Rust 内核与各平台原生客户端的结构。文档分析、项目逻辑和排版能力由核心模块提供，窗口、编辑交互、文件访问及系统集成由平台客户端负责。

当前包含 macOS 和 iPad 客户端：macOS 使用 SwiftUI 与 AppKit，iPad 使用 SwiftUI 与 UIKit。两者共享 Rust 核心和 UniFFI 绑定；macOS 编译与语言服务运行在独立工作进程，iPad 在应用内调用快照编译接口。

## 模块

| 位置 | 职责 |
| --- | --- |
| `crates/typad-core` | 文档逻辑、Typst 快照编译和本地资源解析 |
| `crates/typad-service` | 应用接口及跨语言传递的数据类型 |
| `crates/typad-ffi` | 将服务接口导出给 Swift |
| `bindings/generator` | 运行 UniFFI 官方 Swift 绑定生成器 |
| `macos/TyPad` | macOS 界面、共享文档类型与资源 |
| `ipad` | iPad 界面、应用内编译调度与构建入口 |
| `crates/typad-worker` | 自有隔离工作进程、Tinymist 库适配与版本化 IPC |
| `xtask` | 本地开发检查命令 |
| `ci` | 静态检查、Universal 构建和 GUI 测试脚本 |

`core` 和 `service` 保持平台无关，不依赖 Swift 或特定平台的界面框架。FFI 层主要负责类型声明与调用转发，业务逻辑留在 Rust 服务和核心模块中。UniFFI 的生成器与运行库共用 workspace 中的依赖版本，具体版本由 `Cargo.lock` 固定。

## macOS 文档与编辑状态

当前应用使用 `DocumentGroup` 和 `FileDocument` 管理文档，编辑内容由 Swift 持有。新文档为空白源码，源码统计通过 Rust 服务获取；文件读写交给原生文档机制。

Rust 已接收包含版本号的主文档源码快照，编译结果和诊断关联对应版本，避免旧任务覆盖新内容。后续多文件项目需要把未保存子文件也包含在快照中。

编辑区使用 `NSViewRepresentable` 包装 `NSTextView`，保留原生撤销、输入法组合输入、自动换行及查找替换。Tinymist 补全以 UTF-16 编辑范围插入，并保留撤销；已提供行号与基础词法着色，完整语义高亮、折叠和多光标仍待实现。编译器统一把主文档错误的 UTF-8 字节位置转换为 UTF-16 偏移，AppKit 用于错误跳转。

## macOS 排版与预览

应用为每个文档窗口启动自己的 `typad-worker` Rust 子进程，直接调用 Tinymist crate，未使用官方 CLI、stdio LSP 或外部服务。主进程通过 `WorkerClient` 使用版本化 JSON-lines IPC，发送请求 ID、源码版本、完整未保存源码、文件路径及 UTF-16 光标位置。UniFFI 仍保留轻量的新文档和源码统计接口，不承担 IPC。

工作进程的 `Engine` 持有 Tinymist `LspUniverse` 与 `Analysis`。补全、文档查询和 `compile_world` PDF 导出使用同一文档环境和当前源码覆盖；本地资源及包解析交给 Tinymist。每次请求重置文件读取缓存，以便手动编译能读取磁盘上的新资源。暂未保留成功排版结果供标签补全使用，也未实现跨文件未保存缓冲区和文件监听。

Tinymist 使用固定源码提交 `45b50f0d928e825248fa1c2fcbcd68549e957b5d`，Typst 使用上游要求的 `tinymist/v0.15.1` 扩展分支；`Cargo.lock` 固定具体提交。这是语言分析所需的内部信息导出，普通 crates.io Typst 无法直接满足接口。上游类型留在工作进程内，界面只接收 TyPad 的补全、诊断和编辑范围。

每个窗口的 `PreviewModel` 执行 350 ms 防抖，只保留一个运行编译和一个最新待编译快照。源码或光标变化后丢弃过期结果，失败保留最后成功的 PDF。工作进程顺序执行请求；客户端限制请求 16 MiB、响应 128 MiB，默认超时 60 秒。异常退出、通信故障或超时最多自动重启一次并重传完整快照；再次失败会显示错误，用户可再次编译。关闭窗口终止其子进程。PDF 更新尽量保留页码、页面内位置和缩放。

源码与预览的双向定位需要保留源码范围和排版位置之间的映射。文档大纲、语言服务和编译结果会共同提供导航信息，详见[功能路线图](../ROADMAP.md)。

## macOS 构建链

Xcode 按以下顺序构建应用：

1. `RustBindings` 编译 Rust 库与 `typad-worker`，并生成 Swift 接口、C 头文件和 module map。
2. `TyPadCore` 将生成的 Swift 接口编译为静态库。
3. `TyPad` 编译原生界面并链接 Swift 与 Rust 静态库，将工作进程嵌入应用的 `Contents/MacOS`，启用签名时单独签名工作进程。

Debug 和 Release 均默认生成 Universal 2 应用。Rust 分别编译 `aarch64-apple-darwin` 和 `x86_64-apple-darwin`，再合并静态库。生成文件和构建缓存存放在 DerivedData 中。

`TyPadUITests` 是独立的原生 GUI 测试目标。测试安排和运行方法见[测试说明](../ci/README.md)，本地构建方法见[macOS 开发指南](../macos/README.md)。

## 原生界面与本地化

独立 `Window` 承载欢迎页，文档工作区采用 `NavigationSplitView` 与源码/PDF 分栏。补全使用不获取键盘焦点的 `NSPanel`，macOS 26 使用 `glassEffect`，旧系统回退到原生材质。控件文案、动态状态与错误提示由 `Localizable.xcstrings` 提供中英文；上游文档与编译器诊断保留原文。PDFKit 替换文档时暂时覆盖上一帧，关闭隐式动画，并保留阅读位置与缩放，避免短暂白屏。

## iPad Target

`macos/TyPad.xcodeproj` 同时包含 macOS `TyPad` 和 iPad `TyPad-iPad` 应用 Target；各自依赖平台独立的 Swift 绑定库及 Rust 构建 Target。绑定输出使用配置与 `EFFECTIVE_PLATFORM_NAME` 隔离，避免 macOS、iPad 设备和模拟器产物互相覆盖。

iPad 界面位于 `ipad/Sources/TyPad`，共享 `TypstDocument` 和资源。`LocalPreviewModel` 在后台串行队列调用已有 `compile_document` FFI，使用防抖、单个在途请求和最新待编译快照；读取外部资源期间持有安全作用域权限，过期结果被丢弃。iPad 不启动子进程，当前快照后端不具备 macOS Tinymist 工作进程的包解析、补全和崩溃隔离。具体功能边界见 [iPad 开发指南](../ipad/README.md)。
