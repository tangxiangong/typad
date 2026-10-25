# 架构

TyPad 采用共享 Rust 内核与各平台原生客户端的结构。文档分析、项目逻辑和排版能力由核心模块提供，窗口、编辑交互、文件访问及系统集成由平台客户端负责。

当前只开发 macOS 客户端，使用 SwiftUI 和 AppKit，通过 UniFFI 调用 Rust。后续平台可以复用 Rust 核心和服务接口，并采用适合自身的原生 UI 与绑定方式。

## 模块

| 位置 | 职责 |
| --- | --- |
| `crates/typad-core` | 文档逻辑；后续接入 Typst 编译和资源解析 |
| `crates/typad-service` | 应用接口及跨语言传递的数据类型 |
| `crates/typad-ffi` | 将服务接口导出给 Swift |
| `bindings/generator` | 运行 UniFFI 官方 Swift 绑定生成器 |
| `macos/TyPad` | 应用界面、文档读写和原生交互 |
| `xtask` | 本地开发检查命令 |
| `ci` | 静态检查、Universal 构建和 GUI 测试脚本 |

`core` 和 `service` 保持平台无关，不依赖 Swift 或特定平台的界面框架。FFI 层主要负责类型声明与调用转发，业务逻辑留在 Rust 服务和核心模块中。UniFFI 的生成器与运行库共用 workspace 中的依赖版本，具体版本由 `Cargo.lock` 固定。

## macOS 文档与编辑状态

当前应用使用 `DocumentGroup` 和 `FileDocument` 管理文档，编辑内容由 Swift 持有。新文档模板和源码统计通过 Rust 服务获取；文件读写交给原生文档机制。

随着多文件项目和实时编译的实现，Rust 将接收包含版本号的源码快照。编译结果、诊断和预览位置都关联到对应快照，以避免旧任务覆盖新内容。项目中的未保存子文件也需要包含在快照中。

现有编辑区使用 `TextEditor`。完整编辑器计划采用 AppKit 文本系统，加入行号、语法高亮、补全、折叠和多光标等功能。Rust 使用 UTF-8 字节位置，AppKit 使用 UTF-16 范围，两者之间的转换将集中处理。

## 排版与预览

Typst 编译相关依赖已加入工程，编译接口和预览尚未接通。计划由 Rust 管理编译器、字体、包与资源，macOS 界面负责显示诊断和排版结果；分页 PDF 预览使用 PDFKit。

源码与预览的双向定位需要保留源码范围和排版位置之间的映射。文档大纲、语言服务和编译结果会共同提供导航信息，详见[功能路线图](../ROADMAP.md)。

## macOS 构建链

Xcode 按以下顺序构建应用：

1. `RustBindings` 编译 Rust，并生成 Swift 接口、C 头文件和 module map。
2. `TyPadCore` 将生成的 Swift 接口编译为静态库。
3. `TyPad` 编译原生界面并链接 Swift 与 Rust 静态库。

Debug 和 Release 均默认生成 Universal 2 应用。Rust 分别编译 `aarch64-apple-darwin` 和 `x86_64-apple-darwin`，再合并静态库。生成文件和构建缓存存放在 DerivedData 中。

`TyPadUITests` 是独立的原生 GUI 测试目标。测试安排和运行方法见[测试说明](../ci/README.md)，本地构建方法见[macOS 开发指南](../macos/README.md)。
