#!/bin/sh
set -eu

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
derived_dir="${1:?Derived files directory is required}"
rustup_bin="$(command -v rustup || true)"

if [ -z "$rustup_bin" ]; then
    echo "error: rustup is required to build OpenKey's Rust platform library" >&2
    exit 1
fi

for target in aarch64-apple-darwin x86_64-apple-darwin; do
    "$rustup_bin" run stable cargo build \
        --manifest-path "$repo_dir/rust-platform/Cargo.toml" \
        --release --target "$target"
done

xcrun lipo -create \
    "$repo_dir/rust-platform/target/aarch64-apple-darwin/release/libopenkey_platform.a" \
    "$repo_dir/rust-platform/target/x86_64-apple-darwin/release/libopenkey_platform.a" \
    -output "$derived_dir/libopenkey_platform.a"
