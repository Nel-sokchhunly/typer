fn main() {
    // Tauri serves only ui/, so copy the demo video from docs/img (single source; no symlinks for Windows CI).
    for f in ["demo.webm", "demo.mp4", "demo-poster.jpg"] {
        let src = format!("../docs/img/{f}");
        println!("cargo:rerun-if-changed={src}");
        let dst = format!("ui/{f}");
        println!("cargo:rerun-if-changed={dst}"); // rebuild if a copy is deleted
        std::fs::copy(&src, &dst).expect("copy demo video from docs/img");
    }
    tauri_build::build()
}
