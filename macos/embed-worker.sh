#!/bin/bash
set -euo pipefail
destination="$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/typad-worker"
mkdir -p "$(dirname "$destination")"
cp "$TYPAD_BINDINGS_DIR/typad-worker" "$destination"
chmod +x "$destination"
if [[ "${CODE_SIGNING_ALLOWED:-NO}" == YES ]]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime "$destination"
fi
