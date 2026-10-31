import Cocoa
import InputMethodKit

let server = IMKServer(
    name: Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
    bundleIdentifier: Bundle.main.bundleIdentifier)
_ = server
NSApplication.shared.run()
