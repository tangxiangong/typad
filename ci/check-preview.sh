#!/bin/bash
# Host-native preview state tests; no GUI or application automation.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p target/preview-tests
# The normal app build prepares this worker; a standalone check can build it too.
worker="${TYPAD_TEST_WORKER:-$PWD/target/xcode/Build/Products/TyPadBindings/Debug/typad-worker}"
if [[ ! -x "$worker" ]]; then
    cargo build --locked -p typad-worker
    worker="$PWD/target/debug/typad-worker"
fi
xcrun swiftc -parse-as-library -target arm64-apple-macosx13.0 \
    -module-cache-path target/preview-tests/cache \
    macos/TyPad/Sources/TyPad/WorkerClient.swift \
    macos/TyPad/Sources/TyPad/PreviewModel.swift \
    macos/TyPad/Sources/TyPad/ProjectTemplate.swift \
    macos/TyPad/LogicTests/PreviewModelTests.swift \
    -o target/preview-tests/preview-tests
target/preview-tests/preview-tests "$worker"
