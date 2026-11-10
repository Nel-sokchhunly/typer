import TyperEngine

/// What the Composer needs from the engine; tests wrap the real one to count calls.
public protocol Suggester: AnyObject {
    func suggest(_ input: String, _ k: Int) -> [String]
    func pick(_ input: String, _ index: Int)
}

/// Thin wrapper over the Rust C ABI (engine/typer.h), like macos/Engine.swift.
/// If the data can't load, it suggests nothing and learns nothing, so the keyboard still types Latin.
/// Main thread only: the C engine isn't thread-safe.
public final class Engine: Suggester {
    private let engine: OpaquePointer?

    /// `dataDir` holds the data/out TSVs; `userDir` gets user.tsv, picks.tsv and settings.txt.
    public init(dataDir: String, userDir: String?) {
        engine = typer_new(dataDir, userDir)
    }

    deinit { typer_free(engine) }

    public var loaded: Bool { engine != nil }

    public func suggest(_ input: String, _ k: Int = 9) -> [String] {
        guard k > 0, let engine, let p = typer_suggest(engine, input, UInt32(k)) else { return [] }
        defer { typer_string_free(p) }
        return String(cString: p).split(separator: "\n").map(String.init)
    }

    public func pick(_ input: String, _ index: Int) {
        if index >= 0, let engine { typer_pick(engine, input, UInt32(index)) }
    }

    /// Settings switch ("learn", "english", "generated"); on when the engine can't load.
    public func setting(_ name: String) -> Bool {
        guard let engine else { return true }
        return typer_setting(engine, name)
    }
}
