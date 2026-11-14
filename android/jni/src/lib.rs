//! JNI entry points for the Android Keyboard (`com.chhunly.typer.core.NativeEngine`), a thin layer over the
//! engine like `windows/` is. The engine is not thread-safe: Kotlin calls these from one engine thread only.
//!
//! Strings: Java hands JNI "modified UTF-8" (U+0000 and characters outside the BMP are encoded differently from
//! real UTF-8). `JNIEnv::get_string` / `new_string` convert both ways, so Khmer and emoji arrive intact.

use jni::objects::{JClass, JObjectArray, JString};
use jni::sys::{jboolean, jint, jlong, jobjectArray, JNI_FALSE, JNI_TRUE};
use jni::JNIEnv;
use std::path::Path;
use typer::Engine;

fn string(env: &mut JNIEnv, s: &JString) -> Option<String> {
    if s.is_null() {
        return None;
    }
    env.get_string(s).ok().map(Into::into)
}

/// The engine behind a handle from `nativeNew`; None for 0 (data failed to load).
unsafe fn engine<'a>(handle: jlong) -> Option<&'a mut Engine> {
    (handle as *mut Engine).as_mut()
}

/// 0 if the data can't load (the Keyboard then types Latin). `user_dir` may be null: nothing is learned.
#[no_mangle]
pub extern "system" fn Java_com_chhunly_typer_core_NativeEngine_nativeNew(
    mut env: JNIEnv,
    _: JClass,
    data_dir: JString,
    user_dir: JString,
) -> jlong {
    let Some(data) = string(&mut env, &data_dir) else { return 0 };
    let user = string(&mut env, &user_dir);
    match Engine::load(Path::new(&data), user.as_deref().map(Path::new)) {
        Ok(e) => Box::into_raw(Box::new(e)) as jlong,
        Err(_) => 0,
    }
}

#[no_mangle]
pub extern "system" fn Java_com_chhunly_typer_core_NativeEngine_nativeFree(_: JNIEnv, _: JClass, handle: jlong) {
    if handle != 0 {
        drop(unsafe { Box::from_raw(handle as *mut Engine) });
    }
}

/// The top `k` Suggestions, best first; an empty array on any failure.
#[no_mangle]
pub extern "system" fn Java_com_chhunly_typer_core_NativeEngine_nativeSuggest(
    mut env: JNIEnv,
    _: JClass,
    handle: jlong,
    input: JString,
    k: jint,
) -> jobjectArray {
    let texts: Vec<String> = match (unsafe { engine(handle) }, string(&mut env, &input)) {
        (Some(e), Some(input)) if k > 0 => e.suggest(&input, k as usize).into_iter().map(|s| s.text).collect(),
        _ => Vec::new(),
    };
    to_array(&mut env, &texts).map_or(std::ptr::null_mut(), |a| a.into_raw())
}

fn to_array<'a>(env: &mut JNIEnv<'a>, texts: &[String]) -> jni::errors::Result<JObjectArray<'a>> {
    let array = env.new_object_array(texts.len() as i32, "java/lang/String", JString::default())?;
    for (i, t) in texts.iter().enumerate() {
        let s = env.new_string(t)?;
        env.set_object_array_element(&array, i as i32, &s)?;
        env.delete_local_ref(s)?;
    }
    Ok(array)
}

/// Learn the `index`-th Suggestion for `input` (same order nativeSuggest returned).
#[no_mangle]
pub extern "system" fn Java_com_chhunly_typer_core_NativeEngine_nativePick(
    mut env: JNIEnv,
    _: JClass,
    handle: jlong,
    input: JString,
    index: jint,
) {
    if let (Some(e), Some(input)) = (unsafe { engine(handle) }, string(&mut env, &input)) {
        if index >= 0 {
            let _ = e.pick(&input, index as usize); // learning failure is silent, as in engine/src/ffi.rs
        }
    }
}

/// Whether switch `name` ("english", "learn", "generated", ...) is on; on when the engine is missing.
#[no_mangle]
pub extern "system" fn Java_com_chhunly_typer_core_NativeEngine_nativeSetting(
    mut env: JNIEnv,
    _: JClass,
    handle: jlong,
    name: JString,
) -> jboolean {
    match (unsafe { engine(handle) }, string(&mut env, &name)) {
        (Some(e), Some(name)) if !e.setting(&name) => JNI_FALSE,
        _ => JNI_TRUE,
    }
}
