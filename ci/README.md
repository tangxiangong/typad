# 测试与 CI

TyPad 的 CI 当前覆盖共享 Rust 代码和正在开发的 macOS 客户端，使用 GitHub Actions 执行。工作流位于 [tests.yml](../.github/workflows/tests.yml)，每次推送、提交 Pull Request 或手动运行时触发。同一分支有新的运行时，旧任务会被取消。

## 检查内容

当前流水线分为两个任务，均使用 GitHub Actions 的 `xcode-27` runner，在 macOS 27 和 Xcode 27 环境中运行。其他平台的构建和原生测试会随对应客户端加入。

| 任务 | 内容 |
| --- | --- |
| Rust tests and static checks | Rust 格式、整个 workspace 的 Clippy、单元/集成/文档测试，以及脚本、plist、scheme 和 Swift 语法检查 |
| Universal app and native GUI tests | 前一个任务通过后，构建 Universal 2 应用和测试 runner，检查双架构，再通过 XCUITest 验证编辑、中文/英文/公式预览、撤销和重做 |

当前 GUI 用例从欢迎页新建空白文档，通过编辑菜单粘贴包含中文、英文和简单数学公式的 Typst 源码，自动断言应用预览中的三类内容，再验证撤销、重做及重做后的预览。用例不模拟键盘输入、不切换系统输入法，也不打开系统设置。测试结束时恢复原剪贴板；若用户在测试期间复制了其他内容，则保留用户的新内容。

本地已在 Apple Silicon、macOS 27.0.1 和 Xcode 27.1 下通过全部 CI 检查，包括 Rust 格式、Clippy、单元/集成/文档测试、原生静态检查、完整 Universal 2 测试构建、双架构校验和 XCUITest。远端 CI 运行尚未验证。

## 在本地检查

按改动范围选择检查。仅修改 Swift、Xcode 配置或 macOS 资源时，从仓库根目录运行静态检查，并按需进行受影响的 arm64 Swift 类型检查或构建：

```sh
bash ci/check-macos.sh
```

修改 Rust 代码或其依赖时，再运行相应的 Rust 检查：

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
```

这些命令检查代码与配置，不打开应用窗口。

需要验证 GUI 行为且用户已授权操作应用时，在 arm64 Mac 上运行现有 GUI 测试：

```sh
bash ci/test-gui.sh --arm64
```

GUI 测试需要完整 Xcode、Rust 和可用的 macOS 图形桌面。脚本会构建应用、启动测试实例并操作窗口，结束后关闭测试实例。建议在独立测试环境执行，避免影响正在编辑的文档。

`--arm64` 仅限制本地构建和架构校验为 arm64，仍执行全部 GUI 用例。远端 CI 继续使用不带参数的 `bash ci/test-gui.sh`，构建并校验 arm64、x86_64 Universal 2 应用。

构建输出位于 `target/ci-xcode`，日志和测试报告位于 `target/ci-results`。每次运行使用独立的结果文件名。

## 查看失败原因

在 GitHub Actions 的运行页面，先查看失败步骤的日志，再下载 `macos-test-results` 附件。附件保留 14 天，包含构建日志、GUI 测试日志，以及测试阶段生成的 `.xcresult`。

用 Xcode 打开 `.xcresult`，可以查看失败断言和测试活动记录。若构建阶段已失败，先检查构建日志，此时可能还没有 GUI 测试报告。

流水线使用临时签名供测试运行，不需要发布证书。目前缓存 Cargo 下载的依赖；Xcode 产物每次重新构建。
