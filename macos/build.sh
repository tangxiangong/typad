#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
exec xcodebuild -project "$repo/macos/TyPad.xcodeproj" -scheme TyPad \
    -configuration Debug -derivedDataPath "$repo/target/xcode" \
    -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build "$@"
