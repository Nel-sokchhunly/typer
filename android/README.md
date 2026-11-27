# Typer for Android

The Android Keyboard (an input method) and its Companion app, one APK (app id `com.bayonlabs.typer`, code in `com.chhunly.typer`, minSdk 24).
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
`adb shell run-as com.bayonlabs.typer ls files/user`.

## Signing

- **Debug:** every machine signs with the shared `app/debug.keystore` (password `android`, not a secret), so debug
  builds from any dev update each other on a test phone.
- **Release:** only CI signs, on `v*` tags, with the keystore in the repo secrets `TYPER_KEYSTORE_B64` (base64) and
  `TYPER_KEYSTORE_PASSWORD`. Its `app` key is Typer's app signing key and signs both release files: the GitHub APK
  (`Typer-android-v4.1.0-40100.apk`: version and versionCode) and the AAB for Play. Play App Signing holds a copy
  (SHA-256 `03:DF:7B:78…23:B9:D7`) and accepts it as the upload key, so Play and GitHub installs update each other.
  If it's lost, no GitHub APK can ever update existing installs again: the team keeps two backups. The keystore's
  spare `upload` key is unused; it's there if we ever ask Play for an upload key reset.
- **Version:** the tag sets it: `v4.0.1` → `versionName` 4.0.1, `versionCode` 40001 (Play needs it to go up).
