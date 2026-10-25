#!/bin/bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <Rust library> <Swift output directory>" >&2
    exit 2
fi
library="$1"
destination="$2"
if [[ ! -f "$library" ]]; then
    echo "Rust library does not exist: $library" >&2
    exit 1
fi
root="$(cd "$(dirname "$0")/.." && pwd)"
cargo run --locked --manifest-path "$root/Cargo.toml" -p typad-bindgen -- \
    generate --library "$library" --language swift --no-format --out-dir "$destination" \
    --config "$root/crates/typad-ffi/uniffi.toml"
