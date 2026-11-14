import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let onKey: (String) -> Void
    let onBackspace: () -> Void
    let onReturn: () -> Void
    let onCandidate: (Int) -> Void
    let onLatin: () -> Void
    let onGlobe: () -> Void
    let onMode: () -> Void

    private let margin: CGFloat = 3
    private let gap: CGFloat = 6
    private static let keyHeight: CGFloat = 43
    private static let rowGap: CGFloat = 8
    private let keyHeight = KeyboardView.keyHeight
    private let rowGap = KeyboardView.rowGap
    /// Candidate bar + gap + four rows: the controller sizes the keyboard to exactly this.
    static let height: CGFloat = 4 + 40 + 6 + 4 * keyHeight + 3 * rowGap + 4

    var body: some View {
        GeometryReader { geo in
            let kw = (geo.size.width - 2 * margin - 9 * gap) / 10
            VStack(spacing: 0) {
                candidateBar.zIndex(-1)
                Spacer().frame(height: 6)
                if model.showAll && !model.typed.isEmpty {
                    panel.frame(height: 4 * keyHeight + 3 * rowGap)
                } else {
                    VStack(spacing: rowGap) {
                        ForEach(0..<3, id: \.self) { i in row(i, kw: kw, width: geo.size.width).zIndex(Double(i)) }
                        bottomRow(kw: kw).zIndex(3)
                    }
                }
            }
            .padding(.horizontal, margin)
            .padding(.top, 4)
        }
    }

    // MARK: rows

    private static let letters = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let numbers = ["1234567890", "-/:;()$&@\"", ".,?!'"]
    private static let symbols = ["[]{}#%^*+=", "_\\|~<>€£¥•", ".,?!'"]

    @ViewBuilder private func row(_ i: Int, kw: CGFloat, width: CGFloat) -> some View {
        let chars = Array([Self.letters, Self.numbers, Self.symbols][model.page.rawValue][i])
        let fw = (width - 2 * margin - 7 * kw - 8 * gap) / 2  // function key beside the letters of row 3
        HStack(spacing: gap) {
            if i == 2 {
                if model.page == .letters {
                    KeyView(image: model.shift == .lock ? "capslock.fill" : model.shift == .once ? "shift.fill" : "shift",
                            style: model.shift == .off ? .function : .letter, width: fw, height: keyHeight,
                            action: model.shiftTapped)
                } else {
                    KeyView(text: model.page == .numbers ? "#+=" : "123", style: .function, width: fw, height: keyHeight, fontSize: 16) {
                        model.page = model.page == .numbers ? .symbols : .numbers
                    }
                }
            }
            if i == 1 && model.page == .letters { Color.clear.frame(width: (kw + gap) / 2 - gap) }
            ForEach(chars.indices, id: \.self) { j in
                let c = String(chars[j])
                let shown = model.page == .letters && model.shift != .off ? c.uppercased() : c
                KeyView(text: shown, style: .letter, width: i == 2 && model.page != .letters ? nil : kw, height: keyHeight,
                        popup: true) { onKey(shown) }
            }
            if i == 1 && model.page == .letters { Color.clear.frame(width: (kw + gap) / 2 - gap) }
            if i == 2 {
                KeyView(image: "delete.left", style: .function, width: fw, height: keyHeight, repeats: true, action: onBackspace)
            }
        }
    }

    private func bottomRow(kw: CGFloat) -> some View {
        HStack(spacing: gap) {
            KeyView(text: model.page == .letters ? "123" : "ABC", style: .function, width: kw * 1.35, height: keyHeight, fontSize: 16) {
                model.page = model.page == .letters ? .numbers : .letters
            }
            if model.needsGlobe {
                KeyView(image: "globe", style: .function, width: kw * 1.1, height: keyHeight, action: onGlobe)
            }
            // dimmed when the mode is forced (password, email, URL, number) or a Phrase is open
            KeyView(text: model.mode, style: .mode, width: kw * 1.1, height: keyHeight, fontSize: 16, action: onMode)
                .opacity(model.canToggle ? 1 : 0.4)
            KeyView(text: "space", style: .letter, width: nil, height: keyHeight, fontSize: 16) { onKey(" ") }
            KeyView(text: model.returnLabel, style: model.returnProminent ? .prominent : .function, width: kw * 2.1,
                    height: keyHeight, fontSize: 16, action: onReturn)
        }
    }

    // MARK: candidate bar

    private var candidateBar: some View {
        HStack(spacing: 6) {
            if !model.typed.isEmpty {
                // only the first Suggestion; head-truncated so the end, where the user types, stays visible
                Text(model.suggestions.first ?? model.typed)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1).truncationMode(.head)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .background(Color.accentColor.opacity(0.25))
                    .cornerRadius(8)
                    .onTouchUp { onCandidate(0) }
                barButton(Text("abc").font(.system(size: 16, weight: .semibold))) { onLatin() }  // keep the Latin
                barButton(Image(systemName: model.showAll ? "chevron.up" : "chevron.down")
                    .font(.system(size: 17, weight: .bold))) { model.showAll.toggle() }
            }
        }
        .frame(height: 40)
    }

    /// A bar button with a full-height hit area that, like the keys, fires on touch-up.
    private func barButton<Label: View>(_ label: Label, _ action: @escaping () -> Void) -> some View {
        label.foregroundColor(.primary)
            .frame(width: 52, height: 36)
            .background(KeyStyle.function.background)
            .cornerRadius(8)
            .onTouchUp(action)
    }

    // MARK: all-Suggestions panel

    private var panel: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(model.suggestions.enumerated()), id: \.offset) { i, s in
                    panelRow(AttributedString(s), bold: i == 0) {
                        model.showAll = false
                        onCandidate(i)
                    }
                }
                panelRow(AttributedString(model.typed), tag: "abc") {
                    model.showAll = false
                    onLatin()
                }
            }
        }
        .contentMargins(.vertical, 4, for: .scrollContent)
        .noScrollEdgeBlur()
        .background(KeyStyle.letter.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))  // clips rows, dividers and press highlight
    }

    private func panelRow(_ text: AttributedString, bold: Bool = false, tag: String? = nil,
                          _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Text(text).font(.system(size: 20, weight: bold ? .bold : .regular)).lineSpacing(6)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let tag {
                    Text(tag).font(.system(size: 12)).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.systemGray5)).cornerRadius(4)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .foregroundColor(.primary)
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 12) }
    }
}

/// Called on every key touch-down; the controller plays haptic and click when Full Access allows.
private struct KeyPressKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
    var keyPress: () -> Void {
        get { self[KeyPressKey.self] }
        set { self[KeyPressKey.self] = newValue }
    }
}

enum KeyStyle { case letter, function, prominent, mode }

private func dynamic(light: UIColor, dark: UIColor) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}

extension KeyStyle {
    var background: Color {
        switch self {
        case .letter: return dynamic(light: .white, dark: UIColor(white: 0.42, alpha: 1))
        case .function: return dynamic(light: UIColor(red: 0.68, green: 0.71, blue: 0.75, alpha: 1), dark: UIColor(white: 0.27, alpha: 1))
        case .prominent: return .accentColor
        case .mode: return Color(red: 0.96, green: 0.78, blue: 0.26)  // #f5c842, Typer's yellow (macOS mode badge)
        }
    }
    var foreground: Color {
        switch self {
        case .prominent: return .white
        case .mode: return Color(white: 0.1)  // dark on yellow in light and dark mode
        default: return .primary
        }
    }
}

/// One key. Fires on touch-up inside the key (a plain Button drops fast taps), previews the character above the finger,
/// and with `repeats` fires on touch-down, then again after 0.4 s and every 0.08 s while held.
struct KeyView: View {
    var text: String? = nil
    var image: String? = nil
    let style: KeyStyle
    let width: CGFloat?
    let height: CGFloat
    var fontSize: CGFloat = 22
    var popup = false
    var repeats = false
    let action: () -> Void

    @Environment(\.keyPress) private var keyPress
    @State private var pressed = false
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, height: geo.size.height)
                .background(pressed && !popup ? pressedBackground : style.background)
                .cornerRadius(5)
                .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
                .overlay(alignment: .top) { if pressed && popup, let text { preview(text, width: geo.size.width) } }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !pressed else { return }
                            pressed = true
                            keyPress()
                            if repeats { startRepeating() }
                        }
                        .onEnded { v in
                            pressed = false
                            repeater?.cancel()
                            if repeats { return }
                            if CGRect(origin: .zero, size: geo.size).insetBy(dx: -10, dy: -10).contains(v.location) { action() }
                        })
        }
        .frame(width: width, height: height)
        .zIndex(pressed ? 1 : 0)
        .onDisappear { repeater?.cancel() }
    }

    @ViewBuilder private var content: some View {
        if let text { Text(text).font(.system(size: fontSize)).foregroundColor(style.foreground) }
        else if let image { Image(systemName: image).font(.system(size: 18)).foregroundColor(style.foreground) }
    }

    private var pressedBackground: Color {
        style == .letter ? dynamic(light: UIColor(red: 0.68, green: 0.71, blue: 0.75, alpha: 1), dark: UIColor(white: 0.27, alpha: 1))
            : dynamic(light: .white, dark: UIColor(white: 0.42, alpha: 1))
    }

    private func preview(_ text: String, width: CGFloat) -> some View {
        Text(text).font(.system(size: 36)).foregroundColor(.primary)
            .frame(width: width + 6, height: 52)
            .background(RoundedRectangle(cornerRadius: 8).fill(KeyStyle.letter.background))
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            .offset(y: -46)
            .allowsHitTesting(false)
    }

    private func startRepeating() {
        action()
        repeater = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            while !Task.isCancelled {
                action()
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }
}

private extension View {
    /// iOS 26+ blurs scroll view edges, which smears the whole short candidate bar; turn it off.
    @ViewBuilder func noScrollEdgeBlur() -> some View {
        if #available(iOS 26, *) { scrollEdgeEffectHidden() } else { self }
    }
}

private extension View {
    /// Fires on touch-up unless the finger slid away. A plain Button drops fast taps in a keyboard extension.
    func onTouchUp(_ action: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                if abs(v.translation.width) < 30 && abs(v.translation.height) < 30 { action() }
            })
    }
}
