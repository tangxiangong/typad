#!/bin/bash
# Static native checks; does not launch TyPad.
set -euo pipefail
cd "$(dirname "$0")/.."
for file in macos/*.sh ipad/*.sh bindings/*.sh script/*.sh ci/*.sh; do
    bash -n "$file"
done
plutil -lint ipad/Info.plist macos/Info.plist macos/TyPad.xcodeproj/project.pbxproj
for scheme in macos/TyPad.xcodeproj/xcshareddata/xcschemes/*.xcscheme; do
    xmllint --noout "$scheme"
done
xcrun swiftc -frontend -parse macos/TyPad/Sources/TyPad/*.swift
xcrun swiftc -frontend -parse ipad/Sources/TyPad/*.swift
platform="$(xcrun --show-sdk-platform-path)"
xcrun swiftc -typecheck -module-cache-path target/ci-swift-module-cache \
    -F "$platform/Developer/Library/Frameworks" \
    -I "$platform/Developer/usr/lib" macos/TyPad/UITests/*.swift
