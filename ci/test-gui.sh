#!/bin/bash
# Executes a real application. Intended for an isolated macOS CI desktop.
set -euo pipefail
cd "$(dirname "$0")/.."
architectures=(arm64 x86_64)
if [[ $# -gt 0 ]]; then
    if [[ $# -ne 1 || "$1" != --arm64 ]]; then
        echo "Usage: $0 [--arm64]" >&2
        exit 2
    fi
    architectures=(arm64)
fi
case "$(uname -m)" in
    arm64) host_arch=arm64;;
    x86_64) host_arch=x86_64;;
    *) echo "Unsupported macOS test host" >&2; exit 1;;
esac
mkdir -p target/ci-results
run_id="$(date +%Y%m%d-%H%M%S)-$$"
options=(-project macos/TyPad.xcodeproj -scheme TyPad -configuration Debug
    -derivedDataPath target/ci-xcode -destination "platform=macOS,arch=$host_arch"
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES)
xcodebuild "${options[@]}" "ARCHS=${architectures[*]}" ONLY_ACTIVE_ARCH=NO \
    build-for-testing 2>&1 | tee "target/ci-results/build-$run_id.log"
for arch in "${architectures[@]}"; do
    xcrun lipo -verify_arch "$arch" \
        target/ci-xcode/Build/Products/Debug/TyPad.app/Contents/MacOS/TyPad
done
xcodebuild "${options[@]}" test-without-building \
    -parallel-testing-enabled NO \
    -resultBundlePath "target/ci-results/gui-$run_id.xcresult" \
    2>&1 | tee "target/ci-results/gui-$run_id.log"
