import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let onKey: (String) -> Void
    let onBackspace: () -> Void
    let onReturn: () -> Void
    let onCandidate: (Int) -> Void
    let onLatin: () -> Void
    let onGlobe: () -> Void

    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        VStack(spacing: 6) {
            candidateBar
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(Array(row), id: \.self) { c in key(String(c)) { onKey(String(c)) } }
                    if row == rows.last { key("⌫", width: 48, action: onBackspace) }
                }
            }
            HStack(spacing: 4) {
                if model.needsGlobe { key("🌐", width: 48, action: onGlobe) }
                key("space") { onKey(" ") }
                key("return", width: 80, action: onReturn)
            }
        }
        .padding(4)
    }

    private var candidateBar: some View {
        HStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !model.typed.isEmpty {
                        chip(model.typed, bold: false, onLatin)
                        ForEach(Array(model.suggestions.enumerated()), id: \.offset) { i, s in
                            chip(s, bold: i == 0) { onCandidate(i) }
                        }
                    }
                }
            }
            #if DEBUG
            Text(Memory.label).font(.system(size: 9)).foregroundColor(.secondary)
            #endif
        }
        .frame(height: 36)
    }

    private func chip(_ text: String, bold: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 18, weight: bold ? .bold : .regular))
                .padding(.horizontal, 10).frame(height: 32)
                .background(bold ? Color.accentColor.opacity(0.25) : Color(.systemGray5))
                .cornerRadius(6)
        }.foregroundColor(.primary)
    }

    private func key(_ label: String, width: CGFloat? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 20)).frame(maxWidth: width ?? .infinity, minHeight: 44)
                .background(Color(.systemBackground)).cornerRadius(5)
        }.foregroundColor(.primary)
    }
}
