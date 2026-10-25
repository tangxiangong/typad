# 测试与 CI

TyPad 的 CI 当前覆盖共享 Rust 代码和正在开发的 macOS 客户端，使用 GitHub Actions 执行。工作流位于 [tests.yml](../.github/workflows/tests.yml)，每次推送、提交 Pull Request 或手动运行时触发。同一分支有新的运行时，旧任务会被取消。

## 检查内容

当前流水线分为两个任务，均使用 GitHub Actions 的 `xcode-27` runner，在 macOS 27 和 Xcode 27 环境中运行。其他平台的构建和原生测试会随对应客户端加入。

| 任务 | 内容 |
| --- | --- |
| Rust tests and static checks | Rust 格式、整个 workspace 的 Clippy、单元/集成/文档测试，以及脚本、plist、scheme 和 Swift 语法检查 |
| Universal app and native GUI tests | 前一个任务通过后，构建 Universal 2 应用和测试 runner，检查应用包含 arm64、x86_64，再运行 XCUITest |

当前 GUI 用例验证从欢迎页新建空白文档、键盘编辑、撤销和重做。随着产品功能增加，测试将扩展到保存与重开、项目导航、编译、预览定位和导出。

本地已在 Apple Silicon、macOS 27.0.1 和 Xcode 27.1 下通过全部 CI 检查，包括 Rust 格式、Clippy、单元/集成/文档测试、原生静态检查、完整 Universal 2 测试构建、双架构校验和 XCUITest。远端 CI 运行尚未验证。

## 在本地检查

从仓库根目录运行：

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
bash ci/check-macos.sh
```

这些命令检查代码与配置，不打开应用窗口。

运行 GUI 测试：

```sh
bash ci/test-gui.sh
```

GUI 测试需要完整 Xcode、Rust 和可用的 macOS 图形桌面。脚本会构建应用、启动测试实例并操作窗口，结束后关闭测试实例。建议在独立测试环境执行，避免影响正在编辑的文档。

构建输出位于 `target/ci-xcode`，日志和测试报告位于 `target/ci-results`。每次运行使用独立的结果文件名。

## 查看失败原因

在 GitHub Actions 的运行页面，先查看失败步骤的日志，再下载 `macos-test-results` 附件。附件保留 14 天，包含构建日志、GUI 测试日志，以及测试阶段生成的 `.xcresult`。

用 Xcode 打开 `.xcresult`，可以查看失败断言和测试活动记录。若构建阶段已失败，先检查构建日志，此时可能还没有 GUI 测试报告。

流水线使用临时签名供测试运行，不需要发布证书。目前缓存 Cargo 下载的依赖；Xcode 产物每次重新构建。
