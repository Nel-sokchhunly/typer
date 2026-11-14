# Typer for Android

The Android Keyboard (an input method) and its Companion app, one APK (`com.chhunly.typer`, minSdk 24).
Install steps for users are in the main [README](../README.md#android-preview).

```
python3 data/build.py            # engine data (build.sh runs it too)
android/build.sh                 # engine for arm64-v8a / armeabi-v7a / x86_64 (cargo-ndk) + data -> debug APK
android/build.sh host            # ...and the engine for this machine, for the JVM tests
android/build.sh check           # ...install on the running emulator/device, ask the engine for a Phrase
cd android && ./gradlew testDebugUnitTest    # Composer fixtures (fixtures/composer.json) + English words
android/e2e.sh                   # end-to-end on the emulator: real taps on the real keys (see the script header)
android/e2e.sh compare companion # screenshots next to Gboard; the Companion app
```

Needs the Android SDK (`ANDROID_HOME`, default `~/Library/Android/sdk`) with an NDK, Java 17, Rust with
`cargo install cargo-ndk`; `build.sh` adds the Rust Android targets. The APK is debug-signed; nothing here signs a
release.

## Layout

- `jni/`: thin Rust `cdylib` over `../../engine` with hand-written JNI functions (ADR 0004).
- `app/src/main/java/com/chhunly/typer/core/`: no `android.*` imports, runs in plain JVM tests: `Composer` (port of
  `ios/TyperCore`, kept in step by `fixtures/composer.json`), `Engine` (JNI), `KeyLayout` / `KeyTouches` (dp layout
  and touch rules), `AutoCap`, `CursorDrag`, `Settings`, `EnglishWords`.
- `app/src/main/java/com/chhunly/typer/ime/`: the input method: one custom-drawn `KeyboardView` with Material 3
  colour roles (ADR 0005), `TyperIME` (the controller), `ProxyAdapter` (InputConnection as the Composer's field),
  `EngineData` (copies the TSVs from the APK to `filesDir/data` on first run and after an update).
- `app/src/main/java/com/chhunly/typer/app/`: the Companion app, Jetpack Compose Material 3.
- `app/src/debug/`: debug-only helpers: `EngineCheck` (instrumentation used by `build.sh check`) and `FieldsActivity`
  (password / email / URL / search fields for `e2e.sh`).
- `docs/reference.md`: the measurements the Keyboard is built to, and where each came from (ADR 0006).

Learning lives in `filesDir/user` (`user.tsv`, `picks.tsv`, `settings.txt`); on a debug build:
`adb shell run-as com.chhunly.typer ls files/user`.
