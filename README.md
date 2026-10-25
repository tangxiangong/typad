# TyPad

TyPad 是面向 Typst 的跨平台原生写作工具，采用 [MIT 许可证](LICENSE)，以 Rust 作为共享内核。

当前只开发 macOS 版本，界面使用 SwiftUI 和 AppKit，默认构建为兼容 Apple Silicon 和 Intel Mac 的 Universal 2。其他平台的原生客户端将在后续开发。

TyPad 的开发目标是让长文档写作在一个应用中完成：管理多文件项目、编辑与补全源码、实时查看排版结果、在源码和预览之间定位，以及管理文献、模板和导出成果。完整计划见 [Roadmap](ROADMAP.md)。

## 当前进度

项目处于早期开发阶段。目前已有 `.typ` 文档的新建、打开、编辑和保存代码，以及 Swift 与 Rust 之间的接口。Typst 编译器依赖已加入，实时编译、PDF 预览和其他写作功能正在等待实现。

Rust 测试与静态检查已在本地通过。GitHub Actions 已配置 macOS Universal 构建和原生 GUI 测试，首次远端运行尚未验证。当前没有可供日常使用的正式发布版。

## macOS 开发入门

开发需要 macOS、Xcode 和通过 rustup 安装的 Rust。打开 `macos/TyPad.xcodeproj`，选择 `TyPad` scheme；Xcode 会构建 Rust 库并自动生成 Swift 绑定。

在仓库根目录运行：

```sh
# 基础 Rust 检查
cargo xtask check

# 构建 Universal Debug 应用
bash macos/build.sh
```

命令行构建产物位于 `target/xcode/Build/Products/Debug/TyPad.app`。详细环境配置、运行方式和测试命令见下方文档。

## 文档

- [Roadmap](ROADMAP.md)：完整功能与开发阶段。
- [架构](docs/architecture.md)：模块分工和数据流。
- [macOS 开发](macos/README.md)：Xcode 构建与本地运行。
- [Swift 绑定](bindings/README.md)：Rust 接口如何提供给 Swift。
- [测试与 CI](ci/README.md)：自动检查、GUI 测试及失败排查。
