#!/bin/sh
# macos/build.sh           build build/Typer.app for this Mac
# macos/build.sh install   ...and install it to ~/Library/Input Methods
# macos/build.sh dist      build a universal (Apple Silicon + Intel) build/Typer-macos.zip to share
set -eu
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"

python3 data/build.py >/dev/null

APP=build/Typer.app
SET="$APP/Contents/Resources/Typer Settings.app" # opened from Typer's input menu
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/data" "$SET/Contents/MacOS"

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
    for arch in aarch64 x86_64; do
        cargo build --release --manifest-path settings/Cargo.toml --target "$arch-apple-darwin"
    done
    lipo -create settings/target/aarch64-apple-darwin/release/typer-settings \
        settings/target/x86_64-apple-darwin/release/typer-settings -output "$SET/Contents/MacOS/typer-settings"
else
    cargo build --release --manifest-path engine/Cargo.toml
    swift_build engine/target/release "$APP/Contents/MacOS/Typer"
    cargo build --release --manifest-path settings/Cargo.toml
    cp settings/target/release/typer-settings "$SET/Contents/MacOS/"
fi
cat >"$SET/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>typer-settings</string>
	<key>CFBundleIdentifier</key><string>com.chhunly.typer.settings</string>
	<key>CFBundleName</key><string>Typer Settings</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

cp macos/Info.plist "$APP/Contents/"
cp macos/icon.tiff "$APP/Contents/Resources/"
cp data/out/lexicon.tsv data/out/generated.tsv data/out/ngrams.tsv data/out/english.tsv "$APP/Contents/Resources/data/"
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

    # Double-click installer into ~/Library/Input Methods. Installer drops quarantine, so no xattr step.
    P=build/pkg
    rm -rf "$P" build/Typer.pkg
    mkdir -p "$P/root" "$P/scripts"
    cp -R "$APP" "$P/root/"
    printf '#!/bin/sh\npkill -x Typer || true\n' >"$P/scripts/postinstall" # load the new version
    chmod +x "$P/scripts/postinstall"
    pkgbuild --analyze --root "$P/root" "$P/component.plist" >/dev/null
    # otherwise Installer "upgrades" any Typer.app it finds elsewhere on disk instead of installing
    plutil -replace 0.BundleIsRelocatable -bool NO "$P/component.plist"
    version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" macos/Info.plist)
    pkgbuild --root "$P/root" --component-plist "$P/component.plist" --scripts "$P/scripts" \
        --identifier com.chhunly.inputmethod.Typer.pkg --version "$version" \
        --install-location "/Library/Input Methods" "$P/Typer-component.pkg" >/dev/null
    cat >"$P/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Typer</title>
    <domains enable_anywhere="false" enable_currentUserHome="true" enable_localSystem="false"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <os-version min="13.0"/>
    <choices-outline><line choice="typer"/></choices-outline>
    <choice id="typer" title="Typer"><pkg-ref id="com.chhunly.inputmethod.Typer.pkg"/></choice>
    <pkg-ref id="com.chhunly.inputmethod.Typer.pkg" version="$version">Typer-component.pkg</pkg-ref>
</installer-gui-script>
EOF
    productbuild --distribution "$P/distribution.xml" --package-path "$P" build/Typer.pkg >/dev/null
    rm -rf "$P"
    echo "built: build/Typer.pkg"
    ;;
esac
