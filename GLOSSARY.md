# Glossary

**Sing**: Romanized Khmer as people type it in chat. No strict spelling rule: `nh`, `knh`, `knhom` can all mean ខ្ញុំ.

**Phrase**: The Sing text the user is typing and has not committed yet, e.g. `knhom tov sala`. Space-separated words stay in one Phrase.

**Suggestion**: One Khmer rewrite of the Phrase offered to the user. The first Suggestion rewrites the whole Phrase; others cover single words.

**Pick**: The user choosing a Suggestion. A Pick commits Khmer text and replaces the Phrase.

**Learning**: The engine remembering the user's Picks so they rank higher next time. Stored per device.

**Marked text**: The Phrase shown underlined in the text field while composing, before a Pick.

**Khmer mode / English mode**: On the Sing layout, whether the Keyboard turns Sing into Khmer (ខ) or types Latin as is (EN). Password, email and number fields are always English mode on the Sing layout and cannot switch to the Khmer layout. URL and search fields have no special rule: they behave like any text field.

**Sing layout**: Latin letter keys. The user types Sing (Khmer mode) or plain Latin (English mode).
_Avoid_: Latin page, QWERTY page

**Khmer layout**: Khmer letter keys in the standard Khmer arrangement. Each key types its character straight into the text field: no Phrase, no Suggestions, no Learning. Used to type or fix Khmer directly. Modes do not apply.
_Avoid_: Khmer mode, Khmer page

**Emoji panel**: The view that replaces the keys so the user can pick emoji, reached from the emoji key on either layout. Not a layout: it has no Phrase and no modes, and closing it returns to the layout the user came from.
_Avoid_: emoji keyboard, emoji page, emoji layout

**Keyboard**: The typing surface the user installs (iOS keyboard extension, Android input method, macOS input method).

**Companion app**: The app installed alongside the Keyboard. Its only job is to explain how to enable the Keyboard.
_Avoid_: host app, container app

**Host app**: Any app the user is typing into with the Keyboard (Messages, Telegram, Notes).
