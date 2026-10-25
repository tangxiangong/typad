#!/bin/bash
# Static native checks; does not launch TyPad.
set -euo pipefail
cd "$(dirname "$0")/.."
for file in macos/*.sh bindings/*.sh script/*.sh ci/*.sh; do
    bash -n "$file"
done
plutil -lint macos/Info.plist macos/TyPad.xcodeproj/project.pbxproj
xmllint --noout macos/TyPad.xcodeproj/xcshareddata/xcschemes/TyPad.xcscheme
xcrun swiftc -frontend -parse macos/TyPad/Sources/TyPad/*.swift
platform="$(xcrun --show-sdk-platform-path)"
xcrun swiftc -typecheck -module-cache-path target/ci-swift-module-cache \
    -F "$platform/Developer/Library/Frameworks" \
    -I "$platform/Developer/usr/lib" macos/TyPad/UITests/*.swift
