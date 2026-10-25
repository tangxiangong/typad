#!/bin/bash
# Executes a real application. Intended for an isolated macOS CI desktop.
set -euo pipefail
cd "$(dirname "$0")/.."
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
xcodebuild "${options[@]}" 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    build-for-testing 2>&1 | tee "target/ci-results/build-$run_id.log"
xcrun lipo -verify_arch arm64 x86_64 \
    target/ci-xcode/Build/Products/Debug/TyPad.app/Contents/MacOS/TyPad
xcodebuild "${options[@]}" test-without-building \
    -parallel-testing-enabled NO \
    -resultBundlePath "target/ci-results/gui-$run_id.xcresult" \
    2>&1 | tee "target/ci-results/gui-$run_id.log"
