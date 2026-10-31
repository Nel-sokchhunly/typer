#!/bin/sh
# Build Typer.app; `macos/build.sh install` also installs it to ~/Library/Input Methods.
set -eu
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"

python3 data/build.py >/dev/null
cargo build --release --manifest-path engine/Cargo.toml

APP=build/Typer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/data"
swiftc -O -swift-version 5 -import-objc-header engine/typer.h macos/*.swift \
    -L engine/target/release -ltyper -framework InputMethodKit -framework Cocoa \
    -o "$APP/Contents/MacOS/Typer"
cp macos/Info.plist "$APP/Contents/"
cp macos/icon.tiff "$APP/Contents/Resources/"
cp data/out/lexicon.tsv data/out/ngrams.tsv "$APP/Contents/Resources/data/"
codesign --force --deep -s - "$APP"

if [ "${1:-}" = install ]; then
    DEST="$HOME/Library/Input Methods/Typer.app"
    pkill -x Typer || true  # macOS relaunches it on next keystroke
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "installed: $DEST"
fi
