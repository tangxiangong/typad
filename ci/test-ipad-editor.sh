#!/bin/bash
# Runs the production UIKit editor in an isolated simulator test host (no keyboard synthesis).
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 ]]; then
    echo "Usage: $0 <iPad simulator UUID>" >&2
    exit 2
fi
command -v xcodegen >/dev/null || { echo 'xcodegen is required' >&2; exit 1; }
mkdir -p target/ipad-editor-tests target/ci-results
TYPAD_TEST_ROOT="$PWD" xcodegen generate --spec ipad/EditorTests/project.yml --project target/ipad-editor-tests --project-root target/ipad-editor-tests
run_id="$(date +%Y%m%d-%H%M%S)-$$"
xcodebuild -project target/ipad-editor-tests/TyPadEditorTests.xcodeproj \
    -scheme EditorTests -configuration Debug \
    -derivedDataPath target/ipad-editor-tests/build \
    -destination "platform=iOS Simulator,id=$1" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
    -parallel-testing-enabled NO \
    -resultBundlePath "target/ci-results/ipad-editor-$run_id.xcresult" \
    test 2>&1 | tee "target/ci-results/ipad-editor-$run_id.log"
