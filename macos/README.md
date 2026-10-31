# macOS 开发指南

本文介绍 TyPad 当前正在开发的 macOS 客户端。它使用 Xcode 工程构建，运行目标为 macOS 13 及以上版本。Debug 和 Release 默认生成包含 Apple Silicon 与 Intel 架构的 Universal 2 应用。

## 开发环境

需要安装 Xcode 和通过 rustup 管理的 Rust，并完成 Xcode 的首次启动配置。首次构建会下载 Cargo 依赖；缺少 Apple Rust target 时，构建脚本会通过 rustup 安装。

打开 `macos/TyPad.xcodeproj`，选择 `TyPad` scheme 即可构建。Xcode 自动完成 Rust 编译与 Swift 绑定生成，无须提前准备库文件。

## 命令行构建

在仓库根目录运行：

```sh
bash macos/build.sh
```

这是不启动应用的 Debug 构建，关闭代码签名，产物位于：

```text
target/xcode/Build/Products/Debug/TyPad.app
```

也可以使用 `just build`。构建输出保存在 `target/xcode`，删除该目录后可进行干净构建。

## 运行与调试

```sh
./script/build_and_run.sh          # 构建并打开应用
./script/build_and_run.sh --debug  # 构建后进入 LLDB
./script/build_and_run.sh --logs   # 打开应用并查看系统日志
```

运行脚本会检查是否已有 TyPad 进程。请先保存文档并退出已有应用，再启动新的调试版本。`--telemetry` 当前与 `--logs` 相同；`--verify` 启动应用后检查进程是否存在。

## 工程目标

| 目标 | 用途 |
| --- | --- |
| `RustBindings` | 编译 Rust，生成 Swift/C 绑定 |
| `TyPadCore` | 编译生成的 Swift 接口 |
| `TyPad` | 原生文档应用 |
| `TyPadUITests` | 文档编辑的 XCUITest 用例 |

Debug 和 Release 使用独立的应用标识。当前还没有正式安装包和发布流程。

## 测试与当前进度

```sh
bash ci/check-project.sh  # 项目保存、恢复和冲突逻辑（不启动应用）
bash ci/check-macos.sh  # Swift 语法、shell、plist 和 scheme 检查
# 仅在需要验证 GUI 行为且已获授权时运行：
bash ci/test-gui.sh --arm64  # arm64 构建及现有 GUI 用例，不模拟键盘输入
```

仅修改 Swift 或 macOS 配置时，不运行无关的 Rust 检查。GUI 用例通过编辑菜单粘贴包含中文、英文和简单数学公式的源码，自动验证应用预览及撤销、重做后的内容，保留系统当前输入法，结束后恢复剪贴板。GUI 测试会启动并操作应用，适合在独立测试环境执行。测试日志和 `.xcresult` 保存在 `target/ci-results`。完整说明见[测试 CI](../ci/README.md)。

目前支持 `.typ` 文档的新建、编辑和保存，以及内嵌 Typst 自动/手动编译和 PDFKit 并排预览。`⌘B` 编译、`⌘F` 打开查找替换；编译错误可跳转当前文档，失败时保留最后成功的 PDF。文件夹项目已提供文件树、标签页、固定主文档、多文件未保存快照、冲突保护与恢复；文件管理扩展、分栏编辑和完整语义高亮仍在计划中。未新增永久 GUI 测试；现有独立文档 GUI 用例已执行，新增项目流程另以临时项目做实机验收，覆盖保存、恢复、标签状态和图标。功能计划见[Roadmap](../ROADMAP.md)。

## Tinymist 工作进程

构建时会编译并嵌入自有 `typad-worker`，无需安装 Tinymist CLI。源码栏的辅助菜单提供“代码补全”（Control-Space）和“快速帮助”（Option-Command-I）；补全和帮助显示在光标旁，补全支持上下键、Tab、Esc。两者与 PDF 编译使用同一个 Rust 工作进程；异常退出或超时会自动重启一次并重传未保存源码。

`bash ci/check-worker.sh` 运行宿主逻辑检查，覆盖真实 PDF、Tinymist 补全、Unicode 范围、文档信息，以及强制崩溃/持续崩溃/超时后的恢复。它不会启动 GUI。

UI 使用中英文 String Catalog；macOS 26 的补全面板使用系统 Liquid Glass。已在本机 Apple Silicon、macOS 27.0.1 和 Xcode 27.1 下通过 Universal 2 构建、双架构校验、文档新建与编辑的既有 XCUITest，以及宿主逻辑与静态检查。当前用例通过编辑菜单验证中文、英文和数学公式的应用内预览、撤销和重做。
