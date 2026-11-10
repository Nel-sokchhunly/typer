//! Typer Settings: one window of on/off switches, written to the same settings.txt the input
//! method's engine reads (it picks changes up on the next keystroke). Opened from the macOS input
//! menu, the IBus menu / Preferences, or Windows Settings > Typer > Options and the Start menu.
//! Its Tutorial tab opens by itself on first launch and with `--tutorial`.
#![cfg_attr(windows, windows_subsystem = "windows")]

use std::path::{Path, PathBuf};

/// The input method's user folder (user.tsv, picks.tsv, settings.txt), as each frontend sets it.
fn user_dir() -> PathBuf {
    let env = |k| std::env::var_os(k).map(PathBuf::from);
    if cfg!(windows) {
        env("APPDATA").unwrap_or_default().join("Typer") // windows/src/lib.rs
    } else if cfg!(target_os = "macos") {
        env("HOME").unwrap_or_default().join("Library/Application Support/Typer") // macos/Engine.swift
    } else {
        // linux/ibus-typer.c: g_get_user_data_dir()
        env("XDG_DATA_HOME").unwrap_or_else(|| env("HOME").unwrap_or_default().join(".local/share")).join("typer")
    }
}

/// [(name, on)] for every switch, in display order.
#[tauri::command]
fn get_settings() -> Vec<(String, bool)> {
    let off = typer::read_settings(&user_dir());
    typer::SETTINGS.iter().map(|k| (k.to_string(), !off.contains(*k))).collect()
}

#[tauri::command]
fn set_setting(name: String, on: bool) -> Result<(), String> {
    if !typer::SETTINGS.contains(&name.as_str()) {
        return Err(format!("unknown setting {name}"));
    }
    typer::write_setting(&user_dir(), &name, on).map_err(|e| e.to_string())
}

/// True the first time it runs for `dir`: leaves a `tutorial-seen` file there so it won't again.
fn first_launch(dir: &Path) -> bool {
    let seen = dir.join("tutorial-seen");
    if seen.exists() {
        return false;
    }
    let _ = std::fs::create_dir_all(dir).and_then(|_| std::fs::write(seen, ""));
    true
}

/// (open on the Tutorial, OS: "macos" / "windows" / "linux").
#[tauri::command]
fn welcome() -> (bool, &'static str) {
    let asked = std::env::args().any(|a| a == "--tutorial");
    (first_launch(&user_dir()) || asked, std::env::consts::OS)
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![get_settings, set_setting, welcome])
        .run(tauri::generate_context!())
        .expect("Typer Settings failed to start");
}

#[test]
fn tutorial_opens_once() {
    let dir = std::env::temp_dir().join(format!("typer-tutorial-test-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    assert!(first_launch(&dir));
    assert!(!first_launch(&dir));
    std::fs::remove_dir_all(&dir).unwrap();
}
