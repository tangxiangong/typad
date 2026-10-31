#!/bin/bash
# Host-only project persistence tests. Does not launch or automate the application.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p target/project-tests
xcrun swiftc -parse-as-library -target arm64-apple-macosx13.0 \
    -module-cache-path target/project-tests/cache \
    macos/TyPad/Sources/TyPad/ProjectWorkspace.swift \
    macos/TyPad/LogicTests/ProjectWorkspaceTests.swift \
    -o target/project-tests/workspace-tests
target/project-tests/workspace-tests
xcrun swiftc -parse-as-library -target arm64-apple-macosx13.0 \
    -module-cache-path target/project-tests/cache \
    macos/TyPad/Sources/TyPad/FileIcon.swift \
    macos/TyPad/LogicTests/FileIconTests.swift \
    -o target/project-tests/icon-tests
target/project-tests/icon-tests "$PWD"
