import SwiftUI

@main
struct TyperApp: App {
    var body: some Scene {
        WindowGroup { SetupView() }
    }
}

/// The Companion app's copy in Khmer and English. iOS has no Khmer system language, so the app has its
/// own switch instead of following the phone's language. iOS menu names stay in English, as on the phone.
private struct Copy {
    let steps: [String]
    let aboutTitle: String
    let about: String
    let openSettings: String
    let tryHere: String

    static let khmer = Copy(
        steps: [
            "បើក Settings > General > Keyboard > Keyboards។",
            "ចុច Add New Keyboard ហើយជ្រើស Typer (សរសេរ)។",
            "ចុច Typer (សរសេរ) ក្នុងបញ្ជី ហើយបើក Allow Full Access (ស្រេចចិត្ត សូមមើលខាងក្រោម)។",
            "នៅកន្លែងវាយអក្សរណាមួយ ចុចជាប់គ្រាប់ចុចរូបផែនដី ហើយជ្រើស Typer (សរសេរ)។",
        ],
        aboutTitle: "អំពី Allow Full Access",
        about: "វាសម្រាប់តែការញ័រ និងសំឡេងចុចគ្រាប់ចុចប៉ុណ្ណោះ។ Typer មិនប្រើអ៊ីនធឺណិតទេ ហើយអ្វីដែលអ្នកវាយ មិនចេញពីទូរស័ព្ទរបស់អ្នកឡើយ។ ក្តារចុចនៅតែដំណើរការពេញលេញ ទោះបីអ្នកមិនបើកក៏ដោយ។",
        openSettings: "បើក Settings",
        tryHere: "សាកវាយនៅទីនេះ")

    static let english = Copy(
        steps: [
            "Open Settings > General > Keyboard > Keyboards.",
            "Tap Add New Keyboard and pick Typer (សរសេរ).",
            "Tap Typer (សរសេរ) in the list and turn on Allow Full Access (optional, see below).",
            "In any text field, hold the globe key and choose Typer (សរសេរ).",
        ],
        aboutTitle: "About Allow Full Access",
        about: "It is only for haptic feedback and key click sounds. Typer has no internet access, and nothing you type leaves your phone. The keyboard works fully without it.",
        openSettings: "Open Settings",
        tryHere: "Try typing here")
}

struct SetupView: View {
    @State private var text = ""
    @AppStorage("khmer") private var khmer = true

    var body: some View {
        let copy = khmer ? Copy.khmer : Copy.english
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Language", selection: $khmer) {
                    Text("ខ្មែរ").tag(true)
                    Text("English").tag(false)
                }
                .pickerStyle(.segmented)
                Text("Typer (សរសេរ)").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(copy.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(i + 1)").font(.headline).foregroundColor(.white)
                                .frame(width: 26, height: 26).background(Circle().fill(Color.accentColor))
                            Text(step)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(copy.aboutTitle).font(.headline)
                    Text(copy.about).foregroundColor(.secondary)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground)).cornerRadius(12)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text(copy.openSettings).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                TextField(copy.tryHere, text: $text).textFieldStyle(.roundedBorder)
            }
            .padding()
        }
    }
}
