#!/bin/sh
# android/build.sh          data, the engine for arm64-v8a / armeabi-v7a / x86_64 (cargo-ndk), debug APK
# android/build.sh host     ...also the engine for this machine, for the JVM tests (gradlew test)
# android/build.sh check    ...then install on the running emulator/device and ask the engine for a Phrase
# Output: android/app/build/outputs/apk/debug/app-debug.apk (debug-signed)
set -eu
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
export ANDROID_HOME="$SDK"
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
    ANDROID_NDK_HOME=$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)
    export ANDROID_NDK_HOME
fi

python3 data/build.py >/dev/null

command -v cargo-ndk >/dev/null || cargo install cargo-ndk
for t in aarch64-linux-android armv7-linux-androideabi x86_64-linux-android; do
    rustup target list --installed | grep -qx "$t" || rustup target add "$t"
done

OUT=android/app/build/rust
rm -rf "$OUT"
mkdir -p "$OUT/jniLibs" "$OUT/assets/data"
# cargo-ndk reads the crate from the current directory
(cd android/jni && cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -P 24 -o ../app/build/rust/jniLibs build --release)
for f in lexicon ngrams english generated; do cp "data/out/$f.tsv" "$OUT/assets/data/"; done

case "${1:-}" in host | check) cargo build --release --manifest-path android/jni/Cargo.toml ;; esac

(cd android && ./gradlew --quiet assembleDebug)
APK=android/app/build/outputs/apk/debug/app-debug.apk
echo "built: $APK"

[ "${1:-}" = check ] || exit 0
ADB="$SDK/platform-tools/adb"
"$ADB" install -r "$APK" >/dev/null
"$ADB" shell am instrument -w -e input "'knhom tov sala rean'" com.chhunly.typer/.EngineCheck
