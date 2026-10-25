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
bash ci/check-macos.sh  # Swift 语法、shell、plist 和 scheme 检查
bash ci/test-gui.sh     # Universal 测试构建并运行原生 GUI 测试
```

GUI 测试会启动并操作应用，适合在独立测试环境执行。测试日志和 `.xcresult` 保存在 `target/ci-results`。完整说明见[测试 CI](../ci/README.md)。

目前已有 `.typ` 文档的新建、编辑和保存代码。Typst 编译、PDF 预览及完整项目功能仍在开发计划中；新增的 GUI 用例尚未实际运行。功能计划见[Roadmap](../ROADMAP.md)。
