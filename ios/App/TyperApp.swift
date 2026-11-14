import SwiftUI

@main
struct TyperApp: App {
    @State private var text = ""
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Typer (សរសេរ)").font(.largeTitle)
                Text("Settings > General > Keyboard > Keyboards > Add New Keyboard > សរសេរ > Typer (សរសេរ).")
                TextField("Try typing here", text: $text).textFieldStyle(.roundedBorder)
                Spacer()
            }
            .padding()
        }
    }
}
