# 测试与 CI

TyPad 的 CI 当前覆盖共享 Rust 代码和正在开发的 macOS 客户端，使用 GitHub Actions 执行。工作流位于 [tests.yml](../.github/workflows/tests.yml)，每次推送、提交 Pull Request 或手动运行时触发。同一分支有新的运行时，旧任务会被取消。

## 检查内容

当前流水线分为两个任务，均运行在 `xcode-27` Apple Silicon runner 上，通过 `DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer` 明确选择稳定版 Xcode 27.0（27A266a）。每个任务都会输出宿主系统、架构、Xcode、Swift 和 macOS SDK 信息。其他平台的构建和原生测试会随对应客户端加入。

`glassEffect` 等 API 即使有运行时可用性判断，也需要包含这些 API 的新 SDK 才能编译。最低部署版本仍为 macOS 13，Universal 构建仍包含 arm64 和 x86_64，旧系统继续使用原生材质回退。新 runner 上的 GUI 测试只验证当前 Apple Silicon 宿主，不代表已在 macOS 13 或 Intel 实机完成运行验收。

工具链依据：[GitHub runner 镜像清单](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)、[Apple Xcode 支持范围](https://developer.apple.com/xcode/system-requirements)。

| 任务 | 内容 |
| --- | --- |
| Rust tests and static checks | Rust 格式、整个 workspace 的 Clippy、单元/集成/文档测试，以及脚本、plist、scheme 和 Swift 语法检查 |
| Universal app and native GUI tests | 前一个任务通过后，构建 Universal 2 应用和测试 runner，检查应用包含 arm64、x86_64，再运行 XCUITest |

当前 GUI 用例验证新建文档的初始内容、键盘编辑、撤销和重做。随着产品功能增加，测试将扩展到保存与重开、项目导航、编译、预览定位和导出。

本地 Rust 测试和静态检查已通过；首次远端 CI、完整 Universal 测试构建和 GUI 执行尚未验证。

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
