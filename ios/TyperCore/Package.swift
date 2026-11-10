// swift-tools-version:5.9
import Foundation
import PackageDescription

// TyperEngine = engine/typer.h, linked as libtyper.a. On the Mac (`swift test`) that is the host build:
//   cargo build --release --manifest-path engine/Cargo.toml
// For iOS, link build/ios/Typer.xcframework (ios/build.sh) into the app target instead; its module map
// uses the same module name, so the Swift sources don't change.
let hostEngine = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../engine/target/release").standardized.path

let package = Package(
    name: "TyperCore",
    platforms: [.macOS(.v13), .iOS(.v15)],
    products: [.library(name: "TyperCore", targets: ["TyperCore"])],
    targets: [
        .systemLibrary(name: "TyperEngine"),
        .target(
            name: "TyperCore", dependencies: ["TyperEngine"],
            linkerSettings: [.unsafeFlags(["-L", hostEngine], .when(platforms: [.macOS]))]),
        .testTarget(name: "TyperCoreTests", dependencies: ["TyperCore"]),
    ]
)
