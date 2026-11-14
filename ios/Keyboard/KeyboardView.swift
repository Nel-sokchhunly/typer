import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let onCandidate: (Int) -> Void
    let onLatin: () -> Void

    private let margin = KeyLayout.margin
    private let keyHeight = KeyLayout.keyHeight
    private let rowGap = KeyLayout.rowGap
    static let height = KeyLayout.height

    /// Keys are drawn only; the UIKit TouchLayer above this view takes every touch on them (see TouchLayer).
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if model.showAll && !model.typed.isEmpty {
                    VStack(spacing: 0) {
                        candidateBar
                        Spacer().frame(height: 6)
                        panel.frame(height: 4 * keyHeight + 3 * rowGap)
                    }
                    .padding(.horizontal, margin)
                    .padding(.top, KeyLayout.barTop)
                } else {
                    if !model.typed.isEmpty {
                        candidateBar.padding(.horizontal, margin).padding(.top, KeyLayout.barTop)
                    }
                    let keys = model.keys(width: geo.size.width)
                    ZStack(alignment: .topLeading) {
                        ForEach(keys, id: \.action) { key in
                            keyView(key).frame(width: key.rect.width, height: key.rect.height)
                                .offset(x: key.rect.minX, y: key.rect.minY)
                        }
                        ForEach(keys.filter(isPreviewed), id: \.action) { key in preview(key) }
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea()
    }

    // MARK: keys

    private struct Look { var text: String? = nil; var image: String? = nil; var style = KeyStyle.function; var fontSize: CGFloat = 22 }

    private func look(_ a: KeyAction) -> Look {
        switch a {
        case .char(let c): return Look(text: c, style: .letter)
        case .punct(let p): return Look(text: p, fontSize: 20)
        case .shift:
            return Look(image: model.shift == .lock ? "capslock.fill" : model.shift == .once ? "shift.fill" : "shift",
                        style: model.shift == .off ? .function : .letter)
        case .symbols: return Look(text: model.page == .numbers ? "#+=" : "123", fontSize: 16)
        case .page: return Look(text: model.page == .letters ? "123" : "ABC", fontSize: 16)
        case .backspace: return Look(image: "delete.left")
        case .globe: return Look(image: "globe")
        case .mode: return Look(text: model.mode, style: .mode, fontSize: 16)
        case .space: return Look(text: "space", style: .letter, fontSize: 16)
        case .returnKey: return Look(text: model.returnLabel, style: model.returnProminent ? .prominent : .function, fontSize: 16)
        }
    }

    private func isPressed(_ key: Key) -> Bool { model.pressed.contains { $0.action == key.action } }
    private func isPreviewed(_ key: Key) -> Bool {
        if case .char = key.action { return isPressed(key) }
        return false
    }

    private func keyView(_ key: Key) -> some View {
        let l = look(key.action)
        let previewed = isPreviewed(key)
        let pressedBackground = l.style == .letter ? KeyStyle.function.background : KeyStyle.letter.background
        return Group {
            if let text = l.text { Text(text).font(.system(size: l.fontSize)).foregroundColor(l.style.foreground) }
            else if let image = l.image { Image(systemName: image).font(.system(size: 18)).foregroundColor(l.style.foreground) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isPressed(key) && !previewed ? pressedBackground : l.style.background)
        .cornerRadius(5)
        .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
        .opacity(key.action == .mode && !model.canToggle ? 0.4 : 1)  // dimmed when the mode is forced (password, email, URL, number) or a Phrase is open
    }

    /// The character above the finger.
    private func preview(_ key: Key) -> some View {
        Text(look(key.action).text ?? "").font(.system(size: 36)).foregroundColor(.primary)
            .frame(width: key.rect.width + 6, height: 52)
            .background(RoundedRectangle(cornerRadius: 8).fill(KeyStyle.letter.background))
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            .offset(x: key.rect.minX - 3, y: key.rect.minY - 46)
    }

    // MARK: candidate bar

    private var candidateBar: some View {
        HStack(spacing: 6) {
            if !model.typed.isEmpty {  // idle: the Khmer punctuation keys are drawn with the rest (KeyLayout)
                // only the first Suggestion; head-truncated so the end, where the user types, stays visible
                Text(model.suggestions.first ?? model.typed)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1).truncationMode(.head)
                    .padding(.horizontal, 10)
                    .foregroundColor(KeyStyle.mode.foreground)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .background(KeyStyle.mode.background)  // Typer's yellow, like the ខ/EN key
                    .cornerRadius(8)
                    .onTouchUp { onCandidate(0) }
                barButton(Text("abc").font(.system(size: 16, weight: .semibold))) { onLatin() }  // keep the Latin
                barButton(HStack(spacing: 3) {  // how many Suggestions the panel holds
                    Text("\(model.suggestions.count)").font(.system(size: 16, weight: .semibold))
                    Image(systemName: model.showAll ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .bold))
                }) { model.showAll.toggle() }
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
