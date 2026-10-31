# TyPad

TyPad 是面向 Typst 的跨平台原生写作工具，采用 [MIT 许可证](LICENSE)，以 Rust 作为共享内核。

当前提供 macOS 与 iPad 两个应用 Target，共享 Rust 核心。macOS 使用 SwiftUI 和 AppKit，保留 Universal 2 构建能力；iPad 使用 SwiftUI 和 UIKit，通过应用内 Rust 库完成本地编译。

TyPad 的开发目标是让长文档写作在一个应用中完成：管理多文件项目、编辑与补全源码、实时查看排版结果、在源码和预览之间定位，以及管理文献、模板和导出成果。完整计划见 [Roadmap](ROADMAP.md)。

## 当前 macOS 进度

项目处于早期开发阶段。目前已有 `.typ` 文档的新建、打开、编辑和保存代码，以及 Swift 与 Rust 之间的接口。现已接通内嵌 Typst 编译、自动/手动编译、PDF 并排预览和带位置的错误提示。编辑区使用原生 AppKit 文本系统，支持撤销/重做、自动换行和查找替换。

自动编译在输入停止 350 ms 后运行，可在工具栏暂停；按 `⌘B` 手动编译、`⌘F` 查找。编译失败保留最后成功的预览，并明确提示结果已过期。已保存文档可引用同目录及子目录的本地资源；未保存的主文档使用当前编辑内容。输入代码标识符时自动显示光标旁补全，也可从源码栏菜单选择“代码补全”（Control-Space）；“快速帮助”（Option-Command-I）显示格式化文档信息。补全支持上下键选择、Tab 插入、Esc 关闭。文件夹项目支持已打开文件的未保存缓冲区；资源变更监听、完整语义高亮和源码/预览双向定位仍待实现。

语言分析与 PDF 编译运行在随应用打包的自有 `typad-worker` Rust 子进程中，直接调用 Tinymist crate，不需要安装 Tinymist CLI。每个窗口独立进程；异常退出或超时后最多自动重启一次并重传完整未保存源码，持续失败时显示错误并保留旧预览。

Rust 测试与静态检查已在本地通过。GitHub Actions 已配置 macOS Universal 构建和原生 GUI 测试，首次远端运行尚未验证。当前没有可供日常使用的正式发布版。

启动欢迎窗口提供新建/打开文档或项目，以及可筛选的最近文档与项目；可从 窗口 → 显示欢迎窗口（Control-Command-T）重新打开。工作区采用文档导航、源码和 PDF 三栏布局，顶部可切换编辑、分栏和预览模式。

文件菜单中的“打开项目…”（⌥⌘O）打开普通文件夹；“新建项目…”创建含 `main.typ` 的文件夹。侧栏右键 `.typ` 文件可设为主文档，编辑子文件时仍编译该入口。`⌘S` 保存项目所有已修改文件，另存为导出当前文件副本。项目中的 `.typad.json` 保存入口与标签；本机 Application Support/TyPad/Recovery 保存未保存内容的恢复快照。外部内容变动会阻止覆盖并保留编辑，需另存副本后处理冲突。

## macOS 开发入门

开发需要 macOS、Xcode 和通过 rustup 安装的 Rust。打开 `macos/TyPad.xcodeproj`，选择 `TyPad` scheme；Xcode 会构建 Rust 库并自动生成 Swift 绑定。

在仓库根目录运行：

```sh
# 基础 Rust 检查
cargo xtask check

# 本地构建 arm64 Debug 应用
bash macos/build.sh ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

命令行构建产物位于 `target/xcode/Build/Products/Debug/TyPad.app`。详细环境配置、运行方式和测试命令见下方文档。

## 文档

- [Roadmap](ROADMAP.md)：完整功能与开发阶段。
- [架构](docs/architecture.md)：模块分工和数据流。
- [macOS 开发](macos/README.md)：Xcode 构建与本地运行。
- [Swift 绑定](bindings/README.md)：Rust 接口如何提供给 Swift。
- [测试与 CI](ci/README.md)：自动检查、GUI 测试及失败排查。

界面通过 String Catalog 支持简体中文和英文并跟随系统语言。macOS 26 的工具栏、侧栏和补全面板使用系统 Liquid Glass；旧系统使用原生材质。通用图标采用 SF Symbols，TyPad 标记采用矢量 SVG。

## iPad

同一 Xcode 工程现有两个应用 Target：`TyPad`（macOS）和 `TyPad-iPad`（iPadOS 17+）。iPad 使用原生文档浏览器、UIKit 编辑器和应用内 Rust 编译，支持本地编辑、PDF 预览与导出。构建方式和当前平台功能边界见 [iPad 开发指南](ipad/README.md)。
