#!/bin/bash
# Native arm64 logic verification for the iPad compiler model; no app or simulator launch.
set -euo pipefail
cd "$(dirname "$0")/.."
products="$PWD/target/xcode/Build/Products"
bindings="$products/TyPadBindings/Debug"
if [[ ! -f "$products/Debug/libTyPadCore.a" || ! -f "$bindings/libtypad_ffi.a" ]]; then
    echo 'First run: bash macos/build.sh ARCHS=arm64 ONLY_ACTIVE_ARCH=YES' >&2
    exit 1
fi
mkdir -p target/ipad-logic
xcrun swiftc -parse-as-library -target "arm64-apple-macosx$(xcrun --sdk macosx --show-sdk-version)" \
    -module-cache-path target/ci-swift-module-cache \
    -I "$products/Debug" -I "$bindings/include" \
    ipad/Sources/TyPad/LocalPreviewModel.swift ipad/LogicTests/LocalPreviewModelTests.swift \
    "$products/Debug/libTyPadCore.a" "$bindings/libtypad_ffi.a" \
    -o target/ipad-logic/LocalPreviewModelTests
target/ipad-logic/LocalPreviewModelTests
