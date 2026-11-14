import SwiftUI

@main
struct TyperApp: App {
    var body: some Scene {
        WindowGroup { SetupView() }
    }
}

struct SetupView: View {
    @State private var text = ""

    private let steps = [
        "Open Settings > General > Keyboard > Keyboards.",
        "Tap Add New Keyboard and pick Typer (សរសេរ).",
        "Tap Typer (សរសេរ) in the list and turn on Allow Full Access (optional, see below).",
        "In any text field, hold the globe key and choose Typer (សរសេរ).",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Typer (សរសេរ)").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(i + 1)").font(.headline).foregroundColor(.white)
                                .frame(width: 26, height: 26).background(Circle().fill(Color.accentColor))
                            Text(step)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("About Allow Full Access").font(.headline)
                    Text("It is only for haptic feedback and key click sounds. Typer has no internet access, and nothing you type leaves your phone. The keyboard works fully without it.")
                        .foregroundColor(.secondary)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground)).cornerRadius(12)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text("Open Settings").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                TextField("Try typing here", text: $text).textFieldStyle(.roundedBorder)
            }
            .padding()
        }
    }
}
