# Android Keyboard: reference measurements

What the Android Keyboard is built to. Every row says where the number came from. Nothing from Gboard is in
this repository: no code, icons, drawables, fonts, sounds or layout files. Only the measurements and behaviour
descriptions below, taken by looking at Gboard running on an emulator and by reading public sources.

## How the numbers were taken

- **Device:** Android emulator, Android 16 (API 36) Google Play image, arm64, 1080 x 2400 px at 420 dpi
  (411 x 914 dp). Second width: the same emulator switched with `adb shell wm size 720x1600` and
  `wm density 320` (360 x 800 dp).
- **Gboard:** 15.1.08.726012951 (preloaded with the Play image), default theme ("Gboard default", which
  follows the system dynamic colour), default settings, English (US) QWERTY.
- **Screenshots:** `adb exec-out screencap -p` with the Keyboard open on a plain text field (Contacts,
  "Create contact", First name), light and dark (`adb shell cmd uimode night yes`), at both widths. Saved under
  `build/android/reference/` (not committed).
- **Pixel measurement:** a small script that walks scanlines through each key row and column and reports runs of
  non-background pixels (key edges), plus a corner fit for radii. px to dp = px x 160 / dpi.
- **Settings and timings:** read from Gboard's own Preferences screen (observed values), or from AOSP LatinIME
  (`java/res/values/config-common.xml`, Apache 2.0) where observation could not settle them.
- **REA** (the reverse-engineering toolkit) was not needed: Gboard's resource names are obfuscated in its APK
  (`aapt2 dump resources` shows `0_resource_name_obfuscated` for every dimen), so the APK could not answer
  "what is the key height" any better than the screenshots, and the timings were settled by Gboard's
  settings screen and AOSP defaults.

## Geometry

Widths at 411 dp / 360 dp. "W" is the window width, "k" a letter key width, "g" the horizontal gap.

| What | Gboard 411 dp | Gboard 360 dp | Typer builds | Source |
|---|---|---|---|---|
| Side margin (screen edge to first key) | 4.6 dp (12 px) | 4.5 dp (9 px) | 4.5 dp | screenshots |
| Horizontal gap between keys | 5.3 dp (14 px) | 5.0 dp (10 px) | `W x 0.0129`, clamped 4..6 dp | screenshots |
| Letter key width (row 1) | 35.4 dp | 30.5 dp | `(W - 2 x margin - 9g) / 10` | screenshots; formula reproduces both |
| Row 2 indent | half a key plus half a gap each side | same | `(k + g) / 2` | screenshots |
| Shift and backspace width | 55.6 dp = 1.5k + 0.5g | 48 dp | `1.5k + 0.5g` | screenshots |
| Bottom row | `?123` 1.5k, `,` 1k, emoji 1k, space 4k + 3g, `.` 1k, enter 1.5k | same proportions | `?123` 1.5k, ខ/EN 1k, `,` 1k, space 4k + 3g, `.` 1k, return 1.5k (Typer's mode key takes the emoji key's place) | screenshots |
| Row pitch (key top to next key top) | 59 dp (155 px) | 50.5 dp | `0.07456 x screen height dp - 9.15`, clamped 46..64 dp (the line through both measurements) | screenshots: Gboard scales row height with screen height (914 dp tall: 59; 800 dp tall: 50.5) |
| Key height | 47 dp | 40.5 dp | 0.8 x pitch | screenshots (47/59 = 0.80, 40.5/50.5 = 0.80) |
| Vertical gap between rows | 12 dp | 10 dp | 0.2 x pitch | screenshots |
| Letter key corner radius | 7.0 dp | 6.0 dp | 0.215k (the same corner fit then reads 7.0 dp on Typer at 411 dp) | corner fit on the q key at both widths |
| Space, `,` and `.` corner radius | 7 dp (rounded rectangle, not a pill) | | same as letter keys | corner fit on the space bar |
| `?123` and enter shape | full pill (radius = half the key height) | same | pill | screenshots |
| Top of keyboard to top of row 1 (suggestion strip) | 52 dp | 52 dp | 52 dp: 48 dp strip + 4 dp | screenshots: unchanged across widths and heights |
| Strip dividers | 1 dp wide, 24 dp tall, centred | | 1 dp x 24 dp, outline variant | screenshots |
| Keys area (keyboard top to bottom of the last row) | 276 dp | 244.5 dp | follows from the rows above | screenshots |
| Below the last row | 12 dp, then the system's 48 dp bar for keyboards (hide chevron, keyboard switcher) | | 0.2 x pitch, then the larger of the navigation-bar and tappable-element insets (48 dp with gesture navigation on Android 16) | screenshots; the Keyboard window's insets: navigation bars 24 dp, tappable element 48 dp |

## Labels

| What | Gboard 411 dp | Typer builds | Source |
|---|---|---|---|
| Letter label size | x-height 14.1 dp, capital 18 dp: about 26 sp | 26 sp | glyph spans in the screenshots; Roboto/Google Sans x-height is about 0.53 em |
| Function text (`?123`) | cap height about 13 dp: about 18 sp | 18 sp | screenshots |
| Function icons (shift, backspace, enter) | about 24 dp (backspace 25 x 21 dp) | 24 dp Material Symbols | screenshots |
| Hint digit in the top-right corner of row 1 | glyph 8.4 dp tall: about 12 sp, muted | 12 sp, on surface variant | screenshots |
| Suggestion text | capital about 14 dp: about 19-20 sp | Latin 18 sp; Khmer 20 sp in a 48 dp strip (Khmer stacks need about 1.9 em of line) | screenshots; Khmer sizing is Typer's own (Gboard shows no Khmer here) |

## Colour (Material 3 roles)

Gboard's default theme uses the system's dynamic colour. Sampled colours, matched to the Material 3 tonal roles
of the emulator's default (blue) wallpaper scheme:

| Part | Light | Dark | Role it matches | Typer uses |
|---|---|---|---|---|
| Keyboard background | `#eeedf4` | `#1e1f25` | surface container | surface container |
| Letter keys, space, emoji | `#ffffff` | `#33343a` | surface container lowest (light), surface container highest (dark) | the same, per theme |
| Function keys (shift, backspace, `?123`, `,`, `.`, enter) | `#dce2f9` | `#404659` | secondary container | secondary container |
| Letter labels | `#1a1b20` | light | on surface | on surface |
| Function key icons | `#404659` | | on secondary container | on secondary container |
| Strip dividers | `#c5c6d0` | | outline variant | outline variant |
| Long-press highlight | primary-colour circle behind the selected character | | primary | primary |
| Return key with an action (search, send, go, ...) | not measured (the test field's action was "done", drawn as secondary container) | | | primary / on primary, as the brief asks; secondary container when the field has no action |
| Mode key | (Gboard has none) | | | Typer yellow `#f5c842`, dark text, in every theme |
| Pressed key | the key fades while the preview bubble shows | | | a state layer (on-surface at 12% opacity) |

## Touch behaviour

| What | Value | Source |
|---|---|---|
| Key preview popup | a round bubble about 57 dp across, centred on the key, its bottom just above the key's top; label at key-label size; shown at touch-down; the key under it fades | screenshot taken right after an injected touch-down |
| Preview linger after release | 70 ms | AOSP LatinIME `config_key_preview_linger_timeout` |
| Long-press delay | 300 ms | Gboard Preferences, "Key long press delay: 300 ms" (default); AOSP `config_default_longpress_key_timeout` = 300 |
| Long press on the top row | a panel of alternatives with the hint digit selected (primary-colour circle) | screenshot after holding `e` for 0.8 s |
| "Long press for symbols" | on by default; hint digits shown on q..p | Gboard Preferences; screenshots |
| Backspace repeat | starts after 400 ms, then every 50 ms | AOSP `config_key_repeat_start_timeout` = 400, `config_key_repeat_interval` = 50. Not observable on Gboard: touches injected with `adb shell input motionevent` did not make Gboard repeat, so its own values are unverified |
| Haptic on key press | on by default | Gboard Preferences, "Haptic feedback on keypress: On" |
| Popup on key press | on by default | Gboard Preferences |
| Touch noise filter | 40 ms / 12.6 dp | AOSP `config_touch_noise_threshold_time` / `_distance` (not implemented; listed for reference) |

## Where Typer differs on purpose

- **Strip order:** Typer keeps its iOS order (best Suggestion first and emphasised, then the others, then the
  word as typed in quotes for English) rather than Gboard's (typed word on the left, best in the middle), so
  Typer reads the same on iOS and Android.
- **Strip contents:** Typer's strip holds the Suggestions, the `abc` (keep the Latin) control and the expand
  control with the count; idle, it shows the Khmer or English punctuation row, as on iOS. Gboard's idle strip is
  a toolbar (emoji, GIF, clipboard, settings, theme, mic), which is out of scope.
- **Bottom row:** the ខ/EN mode key takes the place of Gboard's emoji key.
- **Long press:** only the hint digit, no accent alternatives (Sing is ASCII).
