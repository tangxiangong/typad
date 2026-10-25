#!/bin/bash
# TyPad's Xcode bridge. Cargo caches unchanged Rust compilation work.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$PATH:$HOME/.cargo/bin"
command -v cargo >/dev/null || { echo "Install Rust with rustup before building TyPad." >&2; exit 1; }
: "${TYPAD_BINDINGS_DIR:?Missing Xcode bindings directory}"
: "${TYPAD_RUST_TARGET_DIR:?Missing Xcode Rust target directory}"
: "${ARCHS:?Missing Xcode architectures}"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
export CARGO_TARGET_DIR="$TYPAD_RUST_TARGET_DIR"
cd "$project_root"
mode=debug
flags=(--locked -p typad-ffi -p typad-worker)
case "${CONFIGURATION:-Debug}" in
    Debug) ;;
    Release) mode=release; flags+=(--release);;
    *) echo "Unsupported build configuration" >&2; exit 1;;
esac
mkdir -p "$TYPAD_BINDINGS_DIR/include" "$TYPAD_BINDINGS_DIR/generated"
libs=()
workers=()
metadata=""
for cpu in $ARCHS; do
    case "$cpu" in
        arm64) triple=aarch64-apple-darwin;;
        x86_64) triple=x86_64-apple-darwin;;
        *) echo "Unsupported architecture: $cpu" >&2; exit 1;;
    esac
    if command -v rustup >/dev/null; then
        if ! rustup target list --installed | /usr/bin/grep -qx "$triple"; then
            rustup target add "$triple"
        fi
    fi
    cargo build "${flags[@]}" --target "$triple"
    libs+=("$CARGO_TARGET_DIR/$triple/$mode/libtypad_ffi.a")
    workers+=("$CARGO_TARGET_DIR/$triple/$mode/typad-worker")
    metadata="$CARGO_TARGET_DIR/$triple/$mode/libtypad_ffi.dylib"
done
bash bindings/generate-swift.sh "$metadata" "$TYPAD_BINDINGS_DIR/generated"
# Preserve generated-file timestamps so Swift avoids unnecessary recompilation.
for name in TyPadCore.swift TyPadCoreFFI.h TyPadCoreFFI.modulemap; do
    case "$name" in
        *.swift) destination="$TYPAD_BINDINGS_DIR/$name";;
        *.h) destination="$TYPAD_BINDINGS_DIR/include/$name";;
        *) destination="$TYPAD_BINDINGS_DIR/include/module.modulemap";;
    esac
    input="$TYPAD_BINDINGS_DIR/generated/$name"
    if ! cmp -s "$input" "$destination"; then cp "$input" "$destination"; fi
done
xcrun lipo -create "${libs[@]}" -output "$TYPAD_BINDINGS_DIR/combined.a"
if ! cmp -s "$TYPAD_BINDINGS_DIR/combined.a" "$TYPAD_BINDINGS_DIR/libtypad_ffi.a"; then
    mv "$TYPAD_BINDINGS_DIR/combined.a" "$TYPAD_BINDINGS_DIR/libtypad_ffi.a"
else
    rm "$TYPAD_BINDINGS_DIR/combined.a"
fi

xcrun lipo -create "${workers[@]}" -output "$TYPAD_BINDINGS_DIR/typad-worker"
