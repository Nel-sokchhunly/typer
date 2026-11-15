# iOS Emoji panel follows Apple's emoji keyboard, not the Gboard-based spec

The Emoji panel spec (#76) was measured on Gboard: vertical scroll, category bar on top, long-press for skin tones and gender. On iOS we follow Apple's emoji keyboard instead, as ADR 0006 does the other way round for Android: a horizontally scrolling grid with section titles, a bottom bar with `ABC`, category icons (SF Symbols) and delete, gender variants as their own grid cells, and long-press for skin tones only (matching tones; mixed tones for two-person emoji skipped). iPhone users already know that shape, and it needs no new data: `emoji.py` keeps gender variants as separate entries. Search is by English name only on both platforms; there is no Khmer emoji search.

## Consequences

- iOS and Android Emoji panels look different on purpose. Android follows #76 as written, apart from search being English only.
