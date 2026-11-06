#!/bin/sh
# linux/build.sh        build build/linux/ibus-engine-typer + typer-settings
#                       (needs cargo, cc, pkg-config, libibus-1.0-dev, libwebkit2gtk-4.1-dev, libgtk-3-dev)
# linux/build.sh deb    ...and package build/Typer-linux-<arch>.deb (TYPER_VERSION sets its version)
set -eu
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"

python3 data/build.py >/dev/null
cargo build --release --manifest-path engine/Cargo.toml
OUT=build/linux
mkdir -p "$OUT"
# shellcheck disable=SC2046 # pkg-config output is meant to split
cc -O2 -Wall -Wextra -Iengine linux/ibus-typer.c engine/target/release/libtyper.a \
    $(pkg-config --cflags --libs ibus-1.0) -lpthread -ldl -lm -o "$OUT/ibus-engine-typer"
cargo build --release --manifest-path settings/Cargo.toml
cp settings/target/release/typer-settings "$OUT/"
echo "built: $OUT/ibus-engine-typer $OUT/typer-settings"

[ "${1:-}" = deb ] || exit 0
version=${TYPER_VERSION:-0.0.0}
arch=$(dpkg --print-architecture)
P=$OUT/pkg
rm -rf "$P"
install -Dm755 "$OUT/ibus-engine-typer" "$P/usr/lib/ibus-typer/ibus-engine-typer"
install -Dm755 "$OUT/typer-settings" "$P/usr/lib/ibus-typer/typer-settings"
install -Dm644 data/out/lexicon.tsv "$P/usr/share/typer/lexicon.tsv"
install -Dm644 data/out/generated.tsv "$P/usr/share/typer/generated.tsv"
install -Dm644 data/out/ngrams.tsv "$P/usr/share/typer/ngrams.tsv"
install -Dm644 data/out/english.tsv "$P/usr/share/typer/english.tsv"
install -Dm644 docs/img/apple-touch-icon.png "$P/usr/share/typer/icon.png"
mkdir -p "$P/usr/share/ibus/component" "$P/usr/share/applications" "$P/DEBIAN"
# GNOME Settings' Input Sources > Preferences opens ibus-setup-<engine>.desktop (not typer.xml's <setup>,
# which only ibus-setup uses); the same entry puts Typer Settings in the app grid.
cat >"$P/usr/share/applications/ibus-setup-typer.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Typer Settings
Comment=Settings for the Typer Khmer keyboard
Exec=/usr/lib/ibus-typer/typer-settings
Icon=/usr/share/typer/icon.png
Categories=Settings;
EOF
sed "s/@VERSION@/$version/" linux/typer.xml >"$P/usr/share/ibus/component/typer.xml"
# Keep control ASCII: App Center reads it through PackageKit and shows Khmer as ????.
cat >"$P/DEBIAN/control" <<EOF
Package: typer
Provides: ibus-typer
Conflicts: ibus-typer
Replaces: ibus-typer
Version: $version
Architecture: $arch
Maintainer: Nel Sokchhunly <sokchhunlynel@gmail.com>
Depends: ibus, libwebkit2gtk-4.1-0, libgtk-3-0
Section: utils
Priority: optional
Homepage: https://nel-sokchhunly.github.io/typer/
Description: Typer: type Khmer in Latin letters (Sing Khmer)
 An IBus input method. Type "knhom tov sala rean" and pick the Khmer sentence.
 Spell however you chat; it learns from what you pick. Works offline.
EOF
# ibus-daemon only rescans components when it starts; tell the user so instead of killing their session.
cat >"$P/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
echo "Typer installed. Log out and back in, then add Typer under Settings > Keyboard > Input Sources > Khmer."
EOF
chmod 755 "$P/DEBIAN/postinst"
dpkg-deb --build --root-owner-group "$P" "build/Typer-linux-$arch.deb" >/dev/null
rm -rf "$P"
echo "built: build/Typer-linux-$arch.deb"
