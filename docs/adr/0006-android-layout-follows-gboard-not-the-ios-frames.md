# Android layout follows Gboard's conventions, not the iOS key frames

The Android Keyboard keeps the iOS typing behaviour (the Composer, shared fixtures, the strip's order and controls) but not the iOS key frames. Android users expect Gboard's proportions, so key widths, gaps, row height, corner radii, the strip height and the pill-shaped `?123` and return keys come from measurements of Gboard on an emulator, recorded with their sources in `android/docs/reference.md`: only numbers and behaviour descriptions, never Gboard code or assets. Rows scale with the screen height as Gboard's do, and the keys stay clear of the system's 48 dp keyboard bar under gesture navigation. Where Typer's behaviour needs something Gboard lacks, Typer's choice wins and is listed in the reference: the ខ/EN key sits where Gboard has its emoji key; the idle strip shows Typer's punctuation row instead of Gboard's toolbar; Suggestions keep Typer's order (best first, then the others, then the typed word) so the strip reads the same on iOS and Android; long press gives only the hint digit.

## Considered Options

- The iOS frames scaled to Android: familiar to the developer, foreign to Android users (no pill keys, iOS row proportions, a globe key Android doesn't need).
- AOSP LatinIME's defaults: an older layout than today's Gboard; used only where Gboard could not be observed (key repeat timing).
