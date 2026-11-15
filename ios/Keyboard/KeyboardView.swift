import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let onCandidate: (Int) -> Void
    let onLatin: () -> Void
    let onEnglishWord: (Int) -> Void
    let onSlot: () -> Void
    let onEmoji: (String) -> Void
    let onClip: (String) -> Void
    let onClearClips: () -> Void
    let onPinClip: (Clip) -> Void  // pins, or unpins when already Pinned
    let onHold: (EmojiHold) -> Void
    let onSearch: () -> Void
    let onGlobe: () -> Void
    let onLetters: () -> Void
    let onDelete: () -> Void

    private let margin = KeyLayout.margin
    private let keyHeight = KeyLayout.keyHeight
    private let rowGap = KeyLayout.rowGap

    /// Keys are drawn only; the UIKit TouchLayer above this view takes every touch on them (see TouchLayer).
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if model.showEmoji && !model.emojiSearching {
                    EmojiPanel(sections: model.emojiSections, onPick: onEmoji, tones: model.emojiTones, display: model.emojiDisplay, onHold: onHold, onSearch: onSearch,
                               globe: model.needsGlobe, onGlobe: onGlobe, onLetters: onLetters, onDelete: onDelete)
                        .frame(height: model.height)
                    if let p = model.panel { longPressPanel(p) }  // an emoji's skin tones
                } else if model.showAll && !model.typed.isEmpty {
                    VStack(spacing: 0) {
                        candidateBar
                        Spacer().frame(height: 6)
                        panel.frame(height: 4 * keyHeight + 3 * rowGap)
                    }
                    .padding(.horizontal, margin)
                    .padding(.top, KeyLayout.barTop)
                } else {
                    if model.emojiSearching {
                        EmojiSearchBar(query: model.emojiQuery, results: model.emojiResults, onPick: onEmoji)
                            .padding(.horizontal, margin).padding(.top, KeyLayout.barTop)
                    } else if !model.typed.isEmpty {
                        candidateBar.padding(.horizontal, margin).padding(.top, KeyLayout.barTop)
                    } else if !model.englishWords.isEmpty {
                        englishBar.padding(.horizontal, margin).padding(.top, KeyLayout.barTop)
                    }
                    if model.showClipboard { clipboardPanel.padding(.horizontal, margin).offset(y: KeyLayout.rowsTop) }
                    let keys = model.keys(width: geo.size.width)
                    ZStack(alignment: .topLeading) {
                        ForEach(keys, id: \.action) { key in
                            keyView(key).frame(width: key.rect.width, height: key.rect.height)
                                .offset(x: key.rect.minX, y: key.rect.minY)
                        }
                        ForEach(keys.filter(isPreviewed), id: \.action) { key in preview(key) }
                        if let p = model.panel { longPressPanel(p) }
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea()
    }

    // MARK: keys

    private struct Look { var text: String? = nil; var image: String? = nil; var style = KeyStyle.function; var fontSize: CGFloat = 22; var label: String? = nil }

    private func look(_ a: KeyAction) -> Look {
        switch a {
        // iOS draws ◌ under a bare combining mark itself. Khmer keys (12 a row): 20 pt, as Apple's Khmer keyboard.
        case .char(let c): return Look(text: c, style: .letter, fontSize: model.layout == .khmer && model.page == .letters ? 20 : 22)
        case .punct(let p): return Look(text: p, fontSize: 20)
        case .shift:
            return Look(image: model.shift == .lock ? "capslock.fill" : model.shift == .once ? "shift.fill" : "shift",
                        style: model.shift == .off ? .function : .letter)
        case .symbols: return Look(text: model.page == .numbers ? "#+=" : "123", fontSize: 16)
        case .page: return Look(text: model.emojiSearching ? "ABC" : model.page == .letters ? "123" : model.layout == .khmer ? "កខគ" : "ABC", fontSize: 16)
        case .emoji: return Look(image: "face.smiling")
        case .clipboard: return Look(image: "clipboard", style: model.showClipboard ? .mode : .switcher, label: "Clipboard")  // a utility key like the layout switch; yellow while its panel is open
        case .fresh: return Look(image: "clipboard", style: .letter, label: "Paste \(model.fresh ?? "")")  // drawn in keyView: icon and text
        case .backspace: return Look(image: "delete.left")
        case .globe: return Look(image: "globe")
        case .mode: return Look(text: model.mode, style: .mode, fontSize: 16)
        case .space: return Look(style: .letter)  // blank, as on iOS
        case .returnKey where model.emojiSearching: return Look(text: "done", fontSize: 16)
        case .returnKey where !model.returnProminent: return Look(image: "return.left")  // plain return: the arrow, as on iOS
        case .returnKey: return Look(text: model.returnLabel, style: .prominent, fontSize: 16)  // go, search, send: named
        case .slot: return Look(text: model.slotLabel, style: .switcher, fontSize: 16)  // the layout switch, unlike the punctuation
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
        let bar = key.action == .fresh
        // light: letters press grey, function keys white; dark (every key one grey): any key presses lighter
        let pressedBackground = dynamic(light: l.style == .letter ? KeyStyle.functionLight : .white, dark: UIColor(white: 0.42, alpha: 1))
        return Group {
            if key.action == .fresh {
                HStack(spacing: 6) {
                    Image(systemName: "clipboard").font(.system(size: 16))
                    Text(model.fresh == nil ? "Paste" : (model.fresh ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")).font(.system(size: 16)).lineLimit(1).truncationMode(.tail)
                }
                .foregroundColor(l.style.foreground).padding(.horizontal, 8)
                .accessibilityElement(children: .ignore).accessibilityLabel(l.label ?? "")
            } else if let text = l.text {
                Text(text).font(.system(size: l.fontSize)).foregroundColor(l.style.foreground)
                    .lineLimit(1).minimumScaleFactor(0.4).padding(.horizontal, 2)  // shrinks to fit: េះ draws as េ◌◌ះ
            } else if let image = l.image {
                let icon = Image(systemName: image).font(.system(size: 18)).foregroundColor(l.style.foreground)
                if let label = l.label { icon.accessibilityLabel(label) } else { icon }
            }
            else { Color.clear }  // a blank key (space) still needs a view to draw its background on
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isPressed(key) && !previewed ? pressedBackground : bar ? Color.clear : l.style.background)
        .cornerRadius(5)
        .shadow(color: .black.opacity(bar ? 0 : 0.3), radius: 0, x: 0, y: 1)
        .overlay {  // the Fresh clip reads like an iOS QuickType suggestion: plain text between thin dividers
            if bar {
                HStack { divider; Spacer(); divider }
            }
        }
        .opacity(key.action == .mode && !model.canToggle || key.action == .slot && model.layoutForced ? 0.4 : 1)  // dimmed when the mode is forced (password, email, number) or a Phrase is open
    }

    private var divider: some View { Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 0.5).padding(.vertical, 8) }

    /// The character above the finger.
    private func preview(_ key: Key) -> some View {
        Text(look(key.action).text ?? "").font(.system(size: 36)).foregroundColor(.primary)
            .lineLimit(1).minimumScaleFactor(0.5)  // wide Khmer letters (ឈ ឡ ញ) shrink instead of clipping
            .frame(width: key.rect.width + 6, height: 52)
            .background(RoundedRectangle(cornerRadius: 8).fill(KeyStyle.letter.background))
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            .offset(x: key.rect.minX - 3, y: key.rect.minY - 46)
    }

    /// The held key's options; the highlighted one types on release.
    private func longPressPanel(_ p: LongPressPanel) -> some View {
        let all = p.cells.reduce(p.cells[0]) { $0.union($1) }
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(KeyStyle.letter.background)
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                .frame(width: all.width, height: all.height)
            ForEach(p.cells.indices, id: \.self) { i in
                let label = KhmerKeys.optionLabel(for: p.options[i])
                let selected = i == model.panelSelected
                optionText(label)
                    .foregroundColor(selected ? KeyStyle.mode.foreground : .primary)  // Typer's yellow, like the ខ/EN key
                    .frame(width: p.cells[i].width, height: p.cells[i].height)
                    .background(selected ? RoundedRectangle(cornerRadius: 6).fill(KeyStyle.mode.background) : nil)
                    .offset(x: p.cells[i].minX - all.minX, y: 0)
            }
        }
        .offset(x: all.minX, y: all.minY)
    }

    /// A Khmer option at 26 pt (ZWJ, ZWNJ labels small); an emoji drawn at EmojiCellView.drawSize and scaled to
    /// 26 pt, so it caches the small strike (see EmojiCellView).
    @ViewBuilder private func optionText(_ label: String) -> some View {
        if label.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) {
            Text(label).font(.system(size: EmojiCellView.drawSize)).scaleEffect(26 / EmojiCellView.drawSize)
        } else {
            Text(label).font(.system(size: label.count > 1 ? 12 : 26)).lineLimit(1).minimumScaleFactor(0.5)
        }
    }

    // MARK: candidate bar

    private var candidateBar: some View {
        HStack(spacing: 6) {
            if !model.typed.isEmpty {  // idle: the punctuation keys are drawn with the rest (KeyLayout)
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
                barButton(HStack(spacing: 3) {  // how many Suggestions the panel holds
                    Text("\(model.suggestions.count)").font(.system(size: 16, weight: .semibold))
                    Image(systemName: model.showAll ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .bold))
                }) { model.showAll.toggle() }
                slot  // abc: keep the Latin
            }
        }
        .frame(height: 40)
    }

    /// English mode, same order as the Khmer bar: the best word in yellow, the next, then what you typed (in quotes).
    private var englishBar: some View {
        let w = model.englishWords
        let order = Array(w.indices.dropFirst()) + [0]
        return HStack(spacing: 6) {
            ForEach(order, id: \.self) { i in
                Text(i == 0 ? "\u{201C}\(w[0])\u{201D}" : w[i])
                    .font(.system(size: 17, weight: i == 1 ? .bold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundColor(i == 1 ? KeyStyle.mode.foreground : .primary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(i == 1 ? KeyStyle.mode.background : KeyStyle.function.background)
                    .cornerRadius(8)
                    .onTouchUp { onEnglishWord(i) }
            }
            slot
        }
        .frame(height: 40)
    }

    /// The bar's rightmost slot when the bar is drawn here; the idle punctuation bar draws it as a key (KeyLayout).
    private var slot: some View {
        // while composing it is keep-Latin, styled like the chevron; only the layout switch gets the switcher look
        barButton(Text(model.slotLabel).font(.system(size: 16, weight: .semibold)), style: model.typed.isEmpty ? .switcher : .function, onSlot)
    }

    /// A bar button with a full-height hit area that, like the keys, fires on touch-up.
    private func barButton<Label: View>(_ label: Label, style: KeyStyle = .function, _ action: @escaping () -> Void) -> some View {
        label.foregroundColor(style.foreground)
            .frame(width: KeyLayout.slotWidth, height: 36)
            .background(style.background)
            .cornerRadius(8)
            .onTouchUp(action)
    }

    // MARK: all-Suggestions panel

    private var panel: some View {
        scrollPanel {
            ForEach(Array(model.suggestions.enumerated()), id: \.offset) { i, s in
                panelRow(AttributedString(s), number: i + 1, bold: i == 0) {
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

    /// The Clipboard panel: one line per Clip, newest first, then Clear all; or a note while there are none.
    private var clipboardPanel: some View {
        scrollPanel {
            ForEach(Array(model.clips.enumerated()), id: \.offset) { _, c in
                panelRow(AttributedString(c.line), plain: true, pinButton: true) { onClip(c.text) }
                    .overlay(alignment: .trailing) {  // on top of the row, so its taps pin instead of paste
                        Button { onPinClip(c) } label: {
                            Image(systemName: c.isPinned ? "pin.fill" : "pin").font(.system(size: 16))
                                .foregroundColor(c.isPinned ? .primary : .secondary)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel(c.isPinned ? "Unpin" : "Pin")
                    }
            }
            if model.clips.isEmpty {
                Text("Text you copy shows here for an hour").font(.system(size: 16)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 12).padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else if model.clips.contains(where: { !$0.isPinned }) {
                Button(action: onClearClips) {  // an action, not a Clip: red and centred, like iOS's destructive buttons
                    Text("Clear all").font(.system(size: 17, weight: .semibold)).foregroundColor(.red)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
            }
        }
        .frame(height: model.height - KeyLayout.rowsTop - 4)
    }

    private func scrollPanel<Rows: View>(@ViewBuilder _ rows: () -> Rows) -> some View {
        ScrollView {
            VStack(spacing: 0) { rows() }
        }
        .contentMargins(.vertical, 4, for: .scrollContent)
        .noScrollEdgeBlur()
        .background(KeyStyle.letter.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))  // clips rows, dividers and press highlight
    }

    private func panelRow(_ text: AttributedString, number: Int? = nil, bold: Bool = false, tag: String? = nil,
                          plain: Bool = false, pinButton: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !plain {  // a Clip row is one line with no number column
                    Text(number.map(String.init) ?? "").font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundColor(.secondary).frame(width: 20, alignment: .trailing)  // the abc row keeps the space, so text lines up
                }
                Text(text).font(.system(size: 20, weight: bold ? .bold : .regular)).lineSpacing(6)
                    .multilineTextAlignment(.leading).lineLimit(plain ? 1 : nil)  // tail ellipsis
                Spacer(minLength: 0)
                if pinButton { Color.clear.frame(width: 32) }  // room for the pin button laid over the row
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

enum KeyStyle {
    case letter, function, prominent, mode, switcher
    static let functionLight = UIColor(red: 0.68, green: 0.71, blue: 0.75, alpha: 1)
}

private func dynamic(light: UIColor, dark: UIColor) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}

extension KeyStyle {
    var background: Color {
        switch self {
        case .letter: return dynamic(light: .white, dark: UIColor(white: 0.27, alpha: 1))  // iOS 26 dark: every key one grey
        case .function: return dynamic(light: Self.functionLight, dark: UIColor(white: 0.27, alpha: 1))
        case .prominent: return .accentColor
        case .mode: return Color(red: 0xf5 / 255, green: 0xc8 / 255, blue: 0x42 / 255)  // #f5c842, Typer's yellow (macOS mode badge)
        case .switcher: return Color(white: 0.1)  // the app icon's ink, in both modes: a yellow fill would look like the ខ/EN key
        }
    }
    var foreground: Color {
        switch self {
        case .prominent: return .white
        case .mode: return Color(white: 0.1)  // dark on yellow in light and dark mode
        case .switcher: return KeyStyle.mode.background  // Typer's yellow text
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

extension View {
    /// Fires on touch-up unless the finger slid away. A plain Button drops fast taps in a keyboard extension.
    func onTouchUp(_ action: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                if abs(v.translation.width) < 30 && abs(v.translation.height) < 30 { action() }
            })
    }
}
