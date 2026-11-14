# iOS Keyboard UI is plain SwiftUI, not KeyboardKit

KeyboardKit (v11, Nov 2026) is a closed-source binary. Its free tier ships autocomplete as a disabled stub, plugging in our own engine is not documented as free, and Pro (from $50/month) validates its license over the network, which ADR 0003 rules out (Full Access is for haptics only). It does not document Marked text and does nothing for Android. Our layout is small (QWERTY, a 123 page, a candidate bar), so we draw keys ourselves in SwiftUI and keep the existing Composer as the only typing logic.

## Considered Options

- KeyboardKit free tier: gives layouts, callouts and a toolbar shell, but not the parts we need (Suggestions, Marked text).
- KeyboardKit Pro: recurring cost and a Full Access requirement for license checks.
