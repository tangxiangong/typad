#!/bin/bash
# Host-native logic tests only. Never launches or automates the GUI.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
cargo build --locked -p typad-worker
mkdir -p target/worker-tests
xcrun swiftc -parse-as-library -module-cache-path target/worker-tests/cache \
    macos/TyPad/Sources/TyPad/WorkerClient.swift macos/TyPad/LogicTests/WorkerClientTests.swift \
    -o target/worker-tests/client-tests
target/worker-tests/client-tests "$root"
