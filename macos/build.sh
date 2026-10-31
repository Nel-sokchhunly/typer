#!/bin/sh
# macos/build.sh           build build/Typer.app for this Mac
# macos/build.sh install   ...and install it to ~/Library/Input Methods
# macos/build.sh dist      build a universal (Apple Silicon + Intel) build/Typer-macos.zip to share
set -eu
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"

python3 data/build.py >/dev/null

APP=build/Typer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/data"

swift_build() { # $1 = rust lib dir, $2 = output, $3 = optional swiftc target
    swiftc -O -swift-version 5 ${3:+-target "$3"} -import-objc-header engine/typer.h macos/*.swift \
        -L "$1" -ltyper -framework InputMethodKit -framework Cocoa -o "$2"
}

if [ "${1:-}" = dist ]; then
    for arch in aarch64 x86_64; do
        cargo build --release --manifest-path engine/Cargo.toml --target "$arch-apple-darwin"
    done
    swift_build engine/target/aarch64-apple-darwin/release build/Typer-arm64 arm64-apple-macos13
    swift_build engine/target/x86_64-apple-darwin/release build/Typer-x86_64 x86_64-apple-macos13
    lipo -create build/Typer-arm64 build/Typer-x86_64 -output "$APP/Contents/MacOS/Typer"
    rm build/Typer-arm64 build/Typer-x86_64
else
    cargo build --release --manifest-path engine/Cargo.toml
    swift_build engine/target/release "$APP/Contents/MacOS/Typer"
fi

cp macos/Info.plist "$APP/Contents/"
cp macos/icon.tiff "$APP/Contents/Resources/"
cp data/out/lexicon.tsv data/out/ngrams.tsv "$APP/Contents/Resources/data/"
codesign --force --deep -s - "$APP"

case "${1:-}" in
install)
    DEST="$HOME/Library/Input Methods/Typer.app"
    pkill -x Typer || true # macOS relaunches it on next keystroke
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "installed: $DEST"
    ;;
dist)
    rm -f build/Typer-macos.zip
    ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" build/Typer-macos.zip
    echo "built: build/Typer-macos.zip ($(lipo -archs "$APP/Contents/MacOS/Typer"))"
    ;;
esac
