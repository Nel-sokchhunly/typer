import Foundation

/// Thin wrapper over the Rust C ABI (engine/typer.h).
enum Typer {
    static let engine: OpaquePointer? = {
        let data = Bundle.main.resourcePath! + "/data"
        let user = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Typer").path  // user.tsv + picks.tsv live here
        return typer_new(data, user)
    }()

    static func suggest(_ input: String, _ k: UInt32 = 9) -> [String] {
        guard let engine, let p = typer_suggest(engine, input, k) else { return [] }
        defer { typer_string_free(p) }
        return String(cString: p).split(separator: "\n").map(String.init)
    }

    static func pick(_ input: String, _ index: Int) {
        if let engine { typer_pick(engine, input, UInt32(index)) }
    }
}
