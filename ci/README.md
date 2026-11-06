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

项目工作区和多文件 worker 的专项检查：

```sh
bash ci/check-project.sh  # arm64 项目缓冲区、保存、恢复和冲突逻辑
bash ci/check-worker.sh   # worker 快照、补全、编译与异常恢复
```

这些命令检查代码与配置，不打开应用窗口。

需要验证 GUI 行为且用户已授权操作应用时，在 arm64 Mac 上运行现有 GUI 测试：

```sh
bash ci/test-gui.sh --arm64
```

GUI 测试需要完整 Xcode、Rust 和可用的 macOS 图形桌面。脚本会构建应用、启动测试实例并操作窗口，结束后关闭测试实例。建议在独立测试环境执行，避免影响正在编辑的文档。

`--arm64` 仅限制本地构建和架构校验为 arm64，仍执行全部 GUI 用例。远端 CI 继续使用不带参数的 `bash ci/test-gui.sh`，构建并校验 arm64、x86_64 Universal 2 应用。

构建输出位于 `target/ci-xcode`，日志和测试报告位于 `target/ci-results`。每次运行使用独立的结果文件名。

iPad 编辑器的 UIKit 集成测试（需要 XcodeGen 和可用的 iPad 模拟器）：

```sh
bash ci/test-ipad-editor.sh <iPad模拟器UUID>
```

该脚本以 arm64 构建独立测试宿主，直接编译生产 `SourceEditor.swift` 和 `TextChange.swift`，通过 XCTest 在模拟器内运行四项测试：连续粘贴与逐次撤销/重做、跨标签隔离、选区替换与重做失效，UITextInput 文本/组合文本提交，以及撤销到空文档后的字体/颜色保持。编辑器实际获得焦点；测试不合成键盘输入、不切换输入法，写剪贴板前备份完整项目，结束时仅在剪贴板仍属于测试时恢复。生成工程在 `target/ipad-editor-tests`，日志与 `.xcresult` 在 `target/ci-results`。

这是 UIKit 编辑接口集成测试，不替代系统输入法键盘、菜单点击或 PDF 预览的端到端 GUI 验收。2026-10-31 在 iPad Pro 13-inch (M5) / iPadOS 27.2 上执行 4 项，全部通过。

## 查看失败原因

在 GitHub Actions 的运行页面，先查看失败步骤的日志，再下载 `macos-test-results` 附件。附件保留 14 天，包含构建日志、GUI 测试日志，以及测试阶段生成的 `.xcresult`。

用 Xcode 打开 `.xcresult`，可以查看失败断言和测试活动记录。若构建阶段已失败，先检查构建日志，此时可能还没有 GUI 测试报告。

流水线使用临时签名供测试运行，不需要发布证书。目前缓存 Cargo 下载的依赖；Xcode 产物每次重新构建。

`bash ci/check-ipad.sh` 在 macOS arm64 主机上通过真实 FFI 验证 iPad 编译模型，包括项目根目录、未保存子文件优先于磁盘、移除子文件快照后恢复磁盘内容；需先运行 `bash macos/build.sh ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` 生成最新绑定。此检查不等同于 iPad 模拟器或真机 UI 验收。

`check-ipad.sh` 还验证 UTF-16 编辑差异与逆操作（含中文替换、emoji 和组合字符）、应用撤销引擎与原生注册状态/嵌套组的隔离及连续撤销重做；并把仅含中文的 PDF 渲染为像素后检查可见笔画，避免仅靠文本提取遗漏空白字形。`check-project.sh` 覆盖容器路径变化、旧恢复格式迁移和恢复成功通知。

2026-10-31 另通过界面自动化在实际 TyPad 应用点击系统“粘贴”菜单，完成连续两次粘贴/撤销/重做、重做后中英文和公式预览断言、A/B 标签历史隔离。此次发现的空文档重做字体退化已修复，并经上述第四项测试与实际界面复验。证据位于 `target/ci-results/paste-menu-e2e/`。

重复菜单验收时，可打开生成的 `TyPadEditorTests.xcodeproj` 并运行 `EditorTests` scheme 的宿主。先点击 `Prepare clipboard fixture`（完整备份模拟器剪贴板到宿主沙箱，再设置中文、英文、公式样本），切到 TyPad，通过长按后的系统“粘贴”菜单操作。结束后回到宿主点击 `Restore original clipboard`，必须看到 `Original clipboard restored and verified`。若用户在测试期间复制了其他内容，工具保留新内容及备份，不覆盖。宿主仅属于测试工程，不进入 TyPad 产品。

## 工作区补全与排版专项检查

```sh
bash ci/check-project.sh
bash ci/check-preview.sh
bash macos/build.sh ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

`check-project.sh` 包含文件/目录移动、直接字面量引用、恢复、外部冲突、删除后重建、资源变化、历史与跨窗口快照的主机逻辑检查。`check-preview.sh` 使用最近一次 Debug 应用构建的 worker（可用 `TYPAD_TEST_WORKER` 指定路径），检查模板、PDF 中英文/数学内容、精确修订导出、跨文件诊断、过期结果和取消/恢复；缺少 worker 时会先执行 `cargo build --locked -p typad-worker`。这两项均不启动或自动操作应用，也不替代 GUI 验收。

## 2026-11-06 GUI 专项验收

- `bash ci/test-gui.sh --arm64` 完成应用及 runner 构建、arm64 架构校验，并实际执行全部现有用例（1 项）。内容覆盖中文、英文、数学公式预览和撤销/重做后的预览。
- 最终结果：`target/ci-results/gui-20261106-143951-46716.xcresult`，对应 `.log` 为执行日志；未新增 GUI 自动化用例。
- 通过原生菜单和剪贴板操作临时项目 `target/GUI-Acceptance-Nov06`，验收第二编辑器、未保存子文件预览、冲突比较、磁盘再次变化时拒绝旧合并、应用合并与保存、重命名/引用更新、PDF 导出与双页布局。
- 导出 `main.pdf` 后用 PDFKit 检查三页及中英文/数学内容。退出复验覆盖正常保存、取消退出、取消后正常关闭，以及未保存项目选择保存退出后的自动恢复。
- 修复：项目保存前更新文件夹元数据基准，冲突保护仍由逐文件字节比较负责；在显式 AppKit 启动/退出入口记录恢复列表，避免 SwiftUI 保存并关闭文档后丢失项目列表。`ApplePersistenceIgnoreState` 会跳过恢复和相关持久化，避免 GUI 测试污染会话。
- 全程未模拟键盘、未切换输入法或打开系统设置。下列追加验收补齐原先未覆盖的项目。

### 追加完整覆盖

- 页码：新增可点击的跳转按钮，验证 `3 → 2 → 3`；`0`、`4`（三页文档）、`abc`、`-1` 均禁用跳转。按钮与回车入口使用同一跳转逻辑。
- 分隔线：实际拖动侧栏及源码/PDF 分隔线；重启后 AX 位置分别保持 `259.5`、`600`，第三页阅读位置恢复。
- 多项目：A/B 两个独立项目同时编译，取消退出保留编辑，随后逐项目保存退出；核对两个主文档和两项恢复记录，重启恢复各自内容。
- Dock：CUA 无法读取 Dock；经用户明确授权改用 AppleScript 操作 Dock 的普通“退出”。验证取消保护、保存退出及恢复，修复该 Apple Event 入口在 SwiftUI 保存审查前未记录恢复列表的问题。处理时保留并转发原有 Apple Event handler 及其 reply/refcon，不替换原生保存流程。
- 关机来源：经用户确认，仅向 TyPad 发送 `aevt/quit`，参数 `why?` 为枚举 `shut`。取消后收到 `-128`，编辑仍保留；再次发送并保存后退出成功，磁盘与恢复记录正确，重启恢复成功。未触发整机关闭、注销或其他应用退出。
- iPad：旧模拟器缺失 data 目录，首次运行属于环境失败；创建独立 `TyPad GUI Acceptance Nov06`（`057A1EDB-D9F0-4D6E-B85B-49D7C3833D51`，iPad Pro 13-inch M5 / iPadOS 27.2），未清除旧模拟器。arm64 模拟器构建及 `ci/check-ipad.sh` 通过，`ci/test-ipad-editor.sh` 的 4 项现有用例通过。结果为 `target/ci-results/ipad-editor-20261106-144529-50187.xcresult`。
- iPad 实际应用：通过 Files 本地提供方打开多文件夹具，查看中文/英文/数学 PDF，切换主文档/子文件标签并验证主入口不变，旋转横竖屏验证自适应布局，完成导出并用 PDFKit 核对三页及中英文/数学文本。应用共享目录在该新模拟器中无法进入，改用独立 Files 提供方夹具；物理 iPad 未操作。
- 新的 GUI 自动化用例没有加入仓库；上述交互通过当前验收会话完成。最终 macOS 回归为 `target/ci-results/gui-20261106-151109-59920.xcresult`（1 项通过、0 失败）。
