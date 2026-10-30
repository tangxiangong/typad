#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
# Device build by default; simulator builds also use arm64.
platform=iphoneos
destination='generic/platform=iOS'
if [[ "${1:-}" == --simulator ]]; then
    platform=iphonesimulator
    destination='generic/platform=iOS Simulator'
    shift
fi
exec xcodebuild -project "$repo/macos/TyPad.xcodeproj" -scheme TyPad-iPad \
    -configuration Debug -derivedDataPath "$repo/target/xcode" -sdk "$platform" \
    -destination "$destination" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build "$@"
