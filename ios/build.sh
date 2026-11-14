#!/bin/sh
# ios/build.sh          build build/ios/Typer.xcframework (the Rust engine for device + simulator)
# ios/build.sh device   ...then generate the Xcode project, build, and install on the connected iPhone
# ios/build.sh ipa      ...then archive unsigned and zip build/ios/Typer.ipa (re-sign it with Sideloadly etc.)
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
rm -rf "$OUT/data"
mkdir -p "$OUT/data"
for f in lexicon ngrams english generated; do cp "data/out/$f.tsv" "$OUT/data/"; done
echo "built: $OUT/Typer.xcframework"

if [ "${1:-}" = ipa ]; then
    (cd ios && xcodegen generate --quiet)
    rm -rf "$OUT/Typer.xcarchive" "$OUT/ipa" "$OUT/Typer.ipa"
    xcodebuild -project ios/Typer.xcodeproj -scheme Typer -configuration Release -destination 'generic/platform=iOS' \
        -archivePath "$OUT/Typer.xcarchive" CODE_SIGNING_ALLOWED=NO archive -quiet
    mkdir -p "$OUT/ipa/Payload"
    cp -R "$OUT/Typer.xcarchive/Products/Applications/Typer.app" "$OUT/ipa/Payload/"
    (cd "$OUT/ipa" && zip -qry ../Typer.ipa Payload)
    echo "built: $OUT/Typer.ipa"
    exit 0
fi
[ "${1:-}" = device ] || exit 0

# One command onto the plugged-in iPhone: sh ios/build.sh device
(cd ios && xcodegen generate --quiet)
ID=$(xcrun devicectl list devices 2>/dev/null | awk '/connected/ && /physical/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) { print $i; exit } }')
[ -n "$ID" ] || { echo "no connected iPhone (plug in, unlock, trust this Mac)" >&2; exit 1; }
xcodebuild -project ios/Typer.xcodeproj -scheme Typer -configuration Debug -destination "id=$ID" \
    -derivedDataPath "$OUT/derived" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build -quiet
xcrun devicectl device install app --device "$ID" "$OUT/derived/Build/Products/Debug-iphoneos/Typer.app"
