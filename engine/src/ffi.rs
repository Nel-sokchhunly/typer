//! C ABI for frontends (macOS IME now, iOS/Android later). Header: engine/typer.h.
use crate::Engine;
use std::ffi::{c_char, CStr, CString};
use std::path::Path;

unsafe fn str_arg<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() { None } else { CStr::from_ptr(p).to_str().ok() }
}

/// NULL on failure (missing data). `user_dir` may be NULL (no learning persisted).
#[no_mangle]
pub unsafe extern "C" fn typer_new(data_dir: *const c_char, user_dir: *const c_char) -> *mut Engine {
    let Some(data) = str_arg(data_dir) else { return std::ptr::null_mut() };
    match Engine::load(Path::new(data), str_arg(user_dir).map(Path::new)) {
        Ok(e) => Box::into_raw(Box::new(e)),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn typer_free(e: *mut Engine) {
    if !e.is_null() {
        drop(Box::from_raw(e));
    }
}

/// Top `k` suggestions joined by '\n'. Free with typer_string_free.
#[no_mangle]
pub unsafe extern "C" fn typer_suggest(e: *const Engine, input: *const c_char, k: u32) -> *mut c_char {
    let (Some(e), Some(input)) = (e.as_ref(), str_arg(input)) else { return std::ptr::null_mut() };
    let text: Vec<String> = e.suggest(input, k as usize).into_iter().map(|s| s.text).collect();
    CString::new(text.join("\n")).map_or(std::ptr::null_mut(), CString::into_raw)
}

/// Learn the `index`-th suggestion for `input` (same order typer_suggest returned).
#[no_mangle]
pub unsafe extern "C" fn typer_pick(e: *mut Engine, input: *const c_char, index: u32) {
    let (Some(e), Some(input)) = (e.as_mut(), str_arg(input)) else { return };
    if let Some(s) = e.suggest(input, index as usize + 1).get(index as usize).cloned() {
        let _ = e.learn(input, &s); // ponytail: learning failure is silent; surface it if users report lost picks
    }
}

#[no_mangle]
pub unsafe extern "C" fn typer_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}
