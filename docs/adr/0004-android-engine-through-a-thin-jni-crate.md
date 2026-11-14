# Android reaches the engine through a thin JNI crate

The Android Keyboard loads the Rust engine as `libtyper_jni.so`, built from `android/jni`: a `cdylib` crate that depends on `../../engine` by path (like `windows/`) and exports five hand-written JNI functions (new, suggest, pick, setting, free) for `com.chhunly.typer.core.NativeEngine`. The engine's own crate types and C ABI stay as they are. Strings cross with the `jni` crate's conversions, because Java hands JNI "modified UTF-8", which differs from UTF-8 for U+0000 and for characters outside the Basic Multilingual Plane; Khmer suggestions arrive intact and an on-device check (`android/build.sh check`) asks for `knhom tov sala rean`. The engine is not thread-safe, so Kotlin calls it from one engine thread only (the Composer's `Scheduler`), as iOS does with its serial queue. The same crate builds for the host, so the JVM tests run the Kotlin Composer against the real engine.

## Considered Options

- Calling `engine/typer.h` from Kotlin through a C shim: still needs JNI glue, plus manual memory handling for the returned strings.
- uniffi: generated bindings and a runtime for five functions; reconsider if the surface grows.
- Adding `cdylib` to the engine crate: changes the crate every platform builds, and still needs JNI-named exports.
