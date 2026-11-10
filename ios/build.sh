#!/bin/sh
# ios/build.sh   build build/ios/Typer.xcframework (the Rust engine for device + simulator)
set -eu
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"

python3 data/build.py >/dev/null

for t in aarch64-apple-ios aarch64-apple-ios-sim; do
    rustup target list --installed | grep -qx "$t" || rustup target add "$t"
    cargo build --release --manifest-path engine/Cargo.toml --target "$t"
done

OUT=build/ios
H="$OUT/headers"
rm -rf "$OUT/Typer.xcframework" "$H"
mkdir -p "$H"
cp engine/typer.h "$H/"
cat >"$H/module.modulemap" <<MM
module TyperEngine {
    header "typer.h"
    export *
}
MM
xcodebuild -create-xcframework \
    -library engine/target/aarch64-apple-ios/release/libtyper.a -headers "$H" \
    -library engine/target/aarch64-apple-ios-sim/release/libtyper.a -headers "$H" \
    -output "$OUT/Typer.xcframework"
echo "built: $OUT/Typer.xcframework"

# TODO(app build): build the host app + keyboard extension and bundle data/out/*.tsv here.
# Blocked by issue #20: Xcode 16.2 can't compile iOS asset catalogs on this macOS.
