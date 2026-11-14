# Android Keyboard is one custom-drawn View with Material 3 colour roles, not Compose

The Keyboard is a single Android `View` that draws its keys, Suggestion strip, all-Suggestions panel and popups on a Canvas from the dp layout in `core/KeyLayout.kt` and the touch rules in `core/KeyTouches.kt`, the counterpart of the iOS layout plus touch layer (ADR 0002). Jetpack Compose inside an `InputMethodService` needs lifecycle and saved-state owners wired by hand onto the input view, and costs memory and first-frame time in a process the system keeps alive while the user types in other apps; Gboard and AOSP LatinIME also draw their own keys. No third-party keyboard library is used. The view reads Material 3 colour roles instead of hard-coded colours: on Android 14+ the system's dynamic colour roles (`android.R.color.system_*`), on 12-13 the nearest tones of the system palettes, and below 12 a fixed scheme generated from Typer yellow `#f5c842`, so no Material Components dependency is needed. The ខ/EN key is Typer yellow in every theme. Every key, strip slot and panel row is an accessibility node with a label, which TalkBack reads and the end-to-end tests use to find keys. The Companion app is a normal Activity and does use Compose Material 3.

## Consequences

- Text layout in the strip (Khmer stacks, ellipsis, baselines) is done by hand with `TextPaint`; keep it in `KeyboardView`.
- Explore-by-touch (hover, lift to type) is implemented in the view, not inherited from a widget.
