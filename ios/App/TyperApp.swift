import SwiftUI

@main
struct TyperApp: App {
    var body: some Scene {
        WindowGroup { SetupView() }
    }
}

/// Typer's palette: the app icon's ink and cream, and the yellow of the mode key and macOS badge.
private extension Color {
    static let yellow = Color(red: 0xf5 / 255, green: 0xc8 / 255, blue: 0x42 / 255)
    static let ink = Color(red: 0x1a / 255, green: 0x1a / 255, blue: 0x1a / 255)
    static let cream = Color(red: 0xed / 255, green: 0xea / 255, blue: 0xe3 / 255)
    /// Page and card colours that follow light and dark mode.
    static let page = dynamic(light: (0xf7, 0xf5, 0xf0), dark: (0x1d, 0x1c, 0x1a))
    static let card = dynamic(light: (0xff, 0xff, 0xff), dark: (0x2a, 0x29, 0x26))
    static let muted = dynamic(light: (0x5f, 0x5b, 0x53), dark: (0xa8, 0xa2, 0x94))

    static func dynamic(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
        func ui(_ c: (Int, Int, Int)) -> UIColor {
            UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

/// The Companion app's copy in Khmer and English. iOS has no Khmer system language, so the app has its
/// own switch instead of following the phone's language. iOS menu names stay in English, as on the phone.
private struct Copy {
    let tagline: String
    let featuresTitle: String
    let features: [(title: String, detail: String)]
    let setup: String
    let steps: [(title: String, detail: String)]
    let aboutTitle: String
    let about: String
    let openSettings: String
    let tryTitle: String
    let tryHere: String

    static let khmer = Copy(
        tagline: "វាយខ្មែរ ដូចពេលអ្នកឆាត។",
        featuresTitle: "មុខងារ",
        features: [
            ("វាយដូចពេលឆាត", "វាយអក្សរឡាតាំងទាំងឃ្លា ហើយ Typer ប្តូរវាជាខ្មែរ។"),
            ("សរសេរតាមរបៀបអ្នក", "គ្មានច្បាប់តឹងរ៉ឹងទេ៖ nh, knh ឬ knhom សុទ្ធតែបាន ខ្ញុំ។"),
            ("ចាំអ្វីដែលអ្នកជ្រើស", "ពាក្យដែលអ្នកជ្រើសញឹកញាប់ នឹងឡើងមកមុនគេ។"),
            ("របារពាក្យស្នើ", "ពណ៌លឿង៖ ពាក្យស្នើល្អបំផុត។ abc៖ រក្សាអក្សរឡាតាំង។ លេខ៖ មើលពាក្យស្នើទាំងអស់។"),
            ("ខ្មែរ ឬ អង់គ្លេស", "ចុចគ្រាប់ ខ ដើម្បីប្តូរទៅវាយអង់គ្លេសធម្មតា។"),
        ],
        setup: "ការរៀបចំ",
        steps: [
            ("បើក Keyboards", "Settings › General › Keyboard › Keyboards"),
            ("បន្ថែម Typer", "ចុច Add New Keyboard ហើយជ្រើស Typer (សរសេរ)"),
            ("Allow Full Access", "ស្រេចចិត្ត៖ ចុច Typer (សរសេរ) ហើយបើកវា ដើម្បីមានការញ័រ និងសំឡេង"),
            ("ចាប់ផ្តើមវាយ", "ចុចជាប់គ្រាប់ចុចរូបផែនដី ហើយជ្រើស Typer (សរសេរ)"),
        ],
        aboutTitle: "ទូរស័ព្ទរបស់អ្នក ទិន្នន័យរបស់អ្នក",
        about: "Full Access សម្រាប់តែការញ័រ និងសំឡេងចុចប៉ុណ្ណោះ។ Typer មិនប្រើអ៊ីនធឺណិតទេ ហើយអ្វីដែលអ្នកវាយ មិនចេញពីទូរស័ព្ទរបស់អ្នកឡើយ។ ក្តារចុចនៅតែដំណើរការពេញលេញ ទោះបីអ្នកមិនបើកក៏ដោយ។",
        openSettings: "បើក Settings",
        tryTitle: "សាកវាយ",
        tryHere: "knhom tov sala rean")

    static let english = Copy(
        tagline: "Type Khmer the way you chat.",
        featuresTitle: "Features",
        features: [
            ("Type how you chat", "Type a whole phrase in Latin letters and Typer turns it into Khmer."),
            ("Spell it your way", "No strict rules: nh, knh or knhom all give ខ្ញុំ."),
            ("Learns your picks", "Words you pick often come up first."),
            ("The Suggestion bar", "Yellow: the top Suggestion. abc: keep the Latin. The number: see every Suggestion."),
            ("Khmer or English", "Tap the ខ key to switch to plain English typing."),
        ],
        setup: "Setup",
        steps: [
            ("Open Keyboards", "Settings › General › Keyboard › Keyboards"),
            ("Add Typer", "Tap Add New Keyboard and pick Typer (សរសេរ)"),
            ("Allow Full Access", "Optional: tap Typer (សរសេរ) and turn it on for haptics and key sounds"),
            ("Start typing", "Hold the globe key and choose Typer (សរសេរ)"),
        ],
        aboutTitle: "Your phone, your words",
        about: "Full Access is only for haptics and key clicks. Typer has no internet access, and nothing you type leaves your phone. The keyboard works fully without it.",
        openSettings: "Open Settings",
        tryTitle: "Try it",
        tryHere: "knhom tov sala rean")
}

struct SetupView: View {
    @State private var text = ""
    @FocusState private var typing: Bool
    @AppStorage("khmer") private var khmer = true
    /// Khmer stacks vowels and subscripts above and below the line, so wrapped Khmer needs more air.
    private var lineGap: CGFloat { khmer ? 7 : 2 }

    var body: some View {
        let copy = khmer ? Copy.khmer : Copy.english
        ScrollViewReader { scroller in
        ScrollView {
            VStack(spacing: 0) {
                hero(copy)
                VStack(alignment: .leading, spacing: 28) {
                    features(copy)
                    steps(copy)
                    privacy(copy)
                    openSettings(copy)
                    tryIt(copy).id("try")
                }
                .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 40)
                .background(Color.page)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                .offset(y: -24)  // the sheet slides up over the yellow
            }
        }
        .background(alignment: .top) {
            VStack(spacing: 0) { Color.yellow; Color.page }.ignoresSafeArea()  // yellow under the top bounce
        }
        .scrollDismissesKeyboard(.never)
        .contentShape(Rectangle())
        .onTapGesture { typing = false }  // tap outside the field closes the keyboard
        .onChange(of: typing) { _, on in
            guard on else { return }
            // wait for the keyboard to take its space, then lift the field above it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation { scroller.scrollTo("try", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0).background(.ultraThinMaterial) }
        .tint(.ink)
        }
    }

    private func hero(_ copy: Copy) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("ស").font(.system(size: 40)).foregroundColor(.cream)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.ink))
                Spacer()
                languageSwitch
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("សរសេរ").font(.system(size: 52, weight: .bold))
                Text("Typer").font(.system(size: 22, weight: .semibold)).opacity(0.6)
            }
            Text(copy.tagline).font(.system(size: 19, weight: .medium))
        }
        .foregroundColor(.ink)
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow)
    }

    private var languageSwitch: some View {
        HStack(spacing: 0) {
            ForEach([(true, "ខ្មែរ"), (false, "EN")], id: \.0) { isKhmer, label in
                Text(label).font(.system(size: 15, weight: .semibold))
                    .foregroundColor(khmer == isKhmer ? .yellow : .ink)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(Capsule().fill(khmer == isKhmer ? Color.ink : .clear))
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.snappy) { khmer = isKhmer } }
            }
        }
        .padding(3)
        .background(Capsule().stroke(Color.ink, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(khmer ? "ភាសា ខ្មែរ" : "Language, English")
    }

    private func features(_ copy: Copy) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(copy.featuresTitle.uppercased()).font(.system(size: 13, weight: .semibold)).tracking(1.2)
                .foregroundColor(.muted)
            ForEach(Array(copy.features.enumerated()), id: \.offset) { i, feature in
                VStack(alignment: .leading, spacing: 10) {
                    featureDemo(i)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(feature.title).font(.system(size: 17, weight: .semibold))
                        Text(feature.detail).font(.system(size: 15)).foregroundColor(.muted).lineSpacing(lineGap)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.card))
            }
        }
    }

    /// A small picture of each feature, drawn like the keyboard: yellow for Typer's picks, grey for the other keys.
    @ViewBuilder private func featureDemo(_ i: Int) -> some View {
        switch i {
        case 0: PhraseDemo()
        case 1:
            HStack(spacing: 6) {
                ForEach(["nh", "knh", "knhom"], id: \.self) { chip($0, latin: true) }
                arrow
                chip("ខ្ញុំ", yellow: true)
            }
        case 2:
            HStack(spacing: 6) {
                chip("sok", latin: true)
                arrow
                chip("សុខ", yellow: true)
                Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).foregroundColor(.muted)
            }
        case 3:
            HStack(spacing: 6) {
                chip("ខ្ញុំទៅសាលារៀន", yellow: true).frame(maxWidth: .infinity, alignment: .leading)
                chip("abc")
                chip("5 ⌄")
            }
        default:
            HStack(spacing: 6) { chip("ខ", yellow: true); arrow; chip("EN") }
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)).foregroundColor(.muted)
    }

    private func chip(_ text: String, yellow: Bool = false, latin: Bool = false) -> some View {
        Text(text).font(.system(size: 16, weight: .semibold, design: latin ? .monospaced : .default))
            .foregroundColor(yellow ? .ink : .primary)
            .padding(.horizontal, 10).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(yellow ? Color.yellow : Color.primary.opacity(0.08)))
    }

    private func steps(_ copy: Copy) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(copy.setup.uppercased()).font(.system(size: 13, weight: .semibold)).tracking(1.2)
                .foregroundColor(.muted)
            ForEach(Array(copy.steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 14) {
                    Text("\(i + 1)").font(.system(size: 17, weight: .bold)).foregroundColor(.ink)
                        .frame(width: 34, height: 34).background(Circle().fill(Color.yellow))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title).font(.system(size: 17, weight: .semibold))
                        Text(step.detail).font(.system(size: 15)).foregroundColor(.muted).lineSpacing(lineGap)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.card))
            }
        }
    }

    private func privacy(_ copy: Copy) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 20)).foregroundColor(.yellow).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(copy.aboutTitle).font(.system(size: 17, weight: .semibold)).foregroundColor(.yellow)
                Text(copy.about).font(.system(size: 15)).foregroundColor(.cream.opacity(0.85)).lineSpacing(lineGap)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.ink))
    }

    private func openSettings(_ copy: Copy) -> some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        } label: {
            HStack {
                Text(copy.openSettings).font(.system(size: 18, weight: .bold))
                Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.ink)
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(Capsule().fill(Color.yellow))
            .overlay(Capsule().stroke(Color.ink, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func tryIt(_ copy: Copy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(copy.tryTitle.uppercased()).font(.system(size: 13, weight: .semibold)).tracking(1.2)
                .foregroundColor(.muted)
            TextField(copy.tryHere, text: $text, axis: .vertical)
                .font(.system(size: 20))
                .lineLimit(2...5)
                .focused($typing)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.card))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(typing ? Color.yellow : .clear, lineWidth: 2.5))
        }
    }
}

/// Types the Latin a letter at a time, then swaps it for the Khmer, on a loop. Static when Reduce Motion is on.
private struct PhraseDemo: View {
    private let latin = "knhom tov sala rean"
    private let khmer = "ខ្ញុំទៅសាលារៀន"
    @State private var typed = ""
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                HStack(spacing: 8) {
                    Text(latin).font(.system(size: 15, design: .monospaced)).foregroundColor(.muted)
                    Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)).foregroundColor(.muted)
                    Text(khmer).font(.system(size: 18, weight: .bold))
                }
            } else if done {
                Text(khmer).font(.system(size: 20, weight: .bold)).foregroundColor(.ink)
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.yellow))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                Text(typed + "▏").font(.system(size: 17, design: .monospaced)).frame(height: 34)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .lineLimit(1).minimumScaleFactor(0.7)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                typed = ""; done = false
                for c in latin {
                    try? await Task.sleep(for: .milliseconds(85))
                    typed.append(c)
                }
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.snappy) { done = true }
                try? await Task.sleep(for: .seconds(2.2))
            }
        }
    }
}
