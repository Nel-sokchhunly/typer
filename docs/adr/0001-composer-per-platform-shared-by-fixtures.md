# Composer logic lives per platform, kept in sync by shared test fixtures

The Rust engine (Suggestions, Learning) is shared by every Keyboard through its C ABI. The Composer (Phrase handling, Marked text, backspace and cursor rules) is written natively per platform: Swift on iOS, and Kotlin on Android when it starts. We chose this over moving the Composer into Rust because it talks constantly to each platform's text APIs, and porting it before iOS ships would delay the first device build. When Android starts, the Composer tests become one shared fixture file that every platform's Composer must pass, so the copies cannot drift.

## Consequences

- macOS `InputController` is a third copy of these rules; it should join the fixtures too.
- If the copies start drifting despite fixtures, revisit moving the Composer into Rust.
