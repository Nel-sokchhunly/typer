---
status: accepted, supersedes ADR-0003
---

# iOS Full Access also covers clipboard history, with one shared switch

ADR 0003 kept Full Access to haptics and key-click sounds. Clipboard history (#103) needs it too: iOS lets a keyboard read the clipboard only with Full Access, and the only way a Companion app switch can reach the Keyboard is the shared container, which the Keyboard can read only with Full Access. So Full Access now covers haptics, sounds and clipboard history, and the shared container (an App Group) holds settings only, today the clipboard history switch; a free Personal Team can use App Groups (checked with a device build). Clips themselves stay in the Keyboard's own sandbox. Clipboard history is on by default once Full Access is granted; without Full Access it is simply absent, and everything else works as before. We still never use the network, and nothing leaves the phone. The Companion app's setup text says so.

## Considered Options

- No clipboard history on iOS: keeps ADR 0003's promise but leaves iOS behind Android.
- The switch inside the Keyboard (as 0003 intended for settings): no shared container needed, but the user preferred one place for settings, matching Android's Companion app.

## Consequences

- The Companion app cannot see whether Full Access is granted, so its switch is labelled as needing Full Access.
- Learning and other Keyboard state stay in the Keyboard's sandbox; only settings move to the shared container.
