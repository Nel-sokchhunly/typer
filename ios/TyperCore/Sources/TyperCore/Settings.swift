import Foundation

/// The in-keyboard switches in `user_dir/settings.txt`: the `name=on|off` lines the desktop settings
/// app writes and the engine reads (engine/src/lib.rs, read_settings / write_setting). The engine
/// checks the file's mtime on every suggest and pick, so a write applies on the next keystroke.
public struct Settings {
    /// The switches shown on iOS; "badge" isn't (the toggle key always shows the mode).
    public static let names = ["generated", "english", "learn"]

    private let file: URL

    public init(userDir: String) {
        file = URL(fileURLWithPath: userDir).appendingPathComponent("settings.txt")
    }

    /// On unless a line says `name=off`, like the engine; no file means all on.
    public func isOn(_ name: String) -> Bool {
        !lines().contains { line in
            let p = Self.parse(line)
            return p?.name == name && p?.value == "off"
        }
    }

    /// Rewrites `name`'s lines in place, or appends one; every other line keeps its place.
    public func set(_ name: String, _ on: Bool) throws {
        let line = "\(name)=\(on ? "on" : "off")"
        var found = false
        var out = lines().map { l -> String in
            guard Self.parse(l)?.name == name else { return String(l) }
            found = true
            return line
        }
        if !found { out.append(line) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // atomic: the engine never reads half a file
        try (out.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private func lines() -> [Substring] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    /// Rust's `split_once('=')` with both sides trimmed.
    private static func parse(_ line: Substring) -> (name: String, value: String)? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let trim = { (s: Substring) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        return (trim(line[..<eq]), trim(line[line.index(after: eq)...]))
    }
}
