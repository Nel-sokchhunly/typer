import Cocoa
import InputMethodKit

let server = IMKServer(
    name: Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
    bundleIdentifier: Bundle.main.bundleIdentifier)
let candidatesPanel: IMKCandidates = {
    let p = IMKCandidates(server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)!
    p.setSelectionKeys([18, 19, 20, 21, 23, 22, 26, 28, 25])  // keycodes of 1-9, shown as labels
    return p
}()
_ = candidatesPanel
NSApplication.shared.run()
