# Rust 与 Swift 绑定

本文介绍 TyPad 当前 macOS 客户端的 Swift 绑定。该客户端使用 UniFFI 调用共享 Rust 服务，通过 Xcode 构建时会自动生成绑定文件。后续其他平台可以使用各自适合的绑定方式，共享同一服务层。

## 接口放在哪里

| 文件位置 | 内容 |
| --- | --- |
| `crates/typad-service/src/api.rs` | 应用调用的 Rust 操作 |
| `crates/typad-service/src/records.rs` | 接口返回的数据类型 |
| `crates/typad-ffi/src/lib.rs` | UniFFI 导出和远程类型声明 |
| `crates/typad-ffi/uniffi.toml` | Swift 模块名称等生成设置 |
| `bindings/generator` | 官方 UniFFI 命令行生成器 |

当前 Swift 模块名为 `TyPadCore`，底层 C 模块名为 `TyPadCoreFFI`。例如，`SourceSummary` 定义在服务层，再由 FFI 层声明为 UniFFI remote record，因此服务层本身不需要依赖 UniFFI。

修改接口时，先更新 Rust 服务和数据类型，再同步 FFI 声明。下一次 Xcode 构建会重新生成 Swift 接口。生成文件位于 DerivedData，不纳入源码管理。

## 手动生成

排查绑定问题时，可以在仓库根目录执行：

```sh
cargo build --locked -p typad-ffi
bash bindings/generate-swift.sh \
  "$PWD/target/debug/libtypad_ffi.dylib" \
  "$PWD/bindings/generated/swift"
```

脚本接受两个参数：已构建的 Rust 动态库路径和输出目录。上面的命令使用宿主架构构建库，适合检查生成结果；正常应用构建由 Xcode 负责双架构 Rust 静态库的编译和合并。

生成器和运行库共用 `Cargo.lock` 中的 UniFFI 版本。遇到 Swift 接口不匹配时，可检查 Rust 导出声明、生成配置和实际使用的构建目录。

有关应用链接顺序，参见[架构说明](../docs/architecture.md)；完整构建步骤见[macOS 开发指南](../macos/README.md)。
