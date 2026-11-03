# Typer សរសេរ

<img src="docs/img/social.png" alt="Typing nh jg tv sala rean in Notes; Typer suggests ខ្ញុំចង់ទៅសាលារៀន" width="480">

**Illustrated install guide with screenshots: <https://nel-sokchhunly.github.io/typer/>**

Typer lets you type Khmer the way you already chat in Latin letters (Sing Khmer):

```
knhom tov sala rean   →   ខ្ញុំទៅសាលារៀន
anh ot jg tv teas te  →   អញអត់ចង់ទៅផ្ទះទេ
```

It works in any app: Messenger, Telegram, Notes, browsers, and so on.

**Requirements:** macOS 13 (Ventura) or newer on an Apple Silicon or Intel Mac, or Windows 10 / 11 (64-bit).

> Typer is an early preview. Expect wrong suggestions sometimes. It learns from what you pick, so it gets better the more you use it.

## Install on macOS

### 1. Download and install

Download **[Typer.pkg](https://github.com/Nel-sokchhunly/typer/releases/latest/download/Typer.pkg)**, double-click it in Downloads, and click through the installer.

> **macOS says it can't verify Typer?** Typer isn't signed with a paid Apple Developer certificate yet. Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to Typer.pkg, then confirm. On macOS 13 or 14 you can also Control-click Typer.pkg and choose **Open**. Only do this if you got the file from this repo.

**Or with Terminal:** open **Terminal** (press `⌘ Space`, type *Terminal*, press Enter), then paste these lines and press Enter:

```sh
curl -fsSL -o /tmp/Typer-macos.zip https://github.com/Nel-sokchhunly/typer/releases/latest/download/Typer-macos.zip
mkdir -p ~/Library/Input\ Methods
rm -rf ~/Library/Input\ Methods/Typer.app
ditto -x -k /tmp/Typer-macos.zip ~/Library/Input\ Methods/
xattr -dr com.apple.quarantine ~/Library/Input\ Methods/Typer.app
echo "Typer installed"
```

Got the zip from a friend or the [Releases page](https://github.com/Nel-sokchhunly/typer/releases) instead? Put it in Downloads and run:

```sh
cd ~/Downloads
unzip -o Typer-macos.zip
xattr -dr com.apple.quarantine Typer.app
mkdir -p ~/Library/Input\ Methods
rm -rf ~/Library/Input\ Methods/Typer.app
mv Typer.app ~/Library/Input\ Methods/
```

> **Why the `xattr` line?** Typer isn't signed with a paid Apple Developer certificate yet, so macOS blocks it by default when it comes from the internet. This line removes that block for Typer only. Only run it if you trust where you got the zip.

### 2. Turn it on

1. Open **System Settings → Keyboard**.
2. Under **Text Input**, click **Edit…** next to *Input Sources*.
3. Click **+** at the bottom left, choose **Khmer** in the list, select **Typer សរសេរ**, and click **Add**.

If Typer isn't in the list, **log out and log back in** (Apple menu → Log Out), then try again.

### 3. Use it

Switch to Typer with **`Ctrl Space`** or the **🌐 Globe** key. You can also pick it from the input menu in the menu bar.

Type Khmer in Latin letters, with spaces between words. A list of suggestions appears under your text.

| Key | What it does |
|---|---|
| `↓` / `↑` | Move through the suggestions (wraps around) |
| `Enter` | Insert the highlighted suggestion (the first one unless you moved) |
| `1` to `9` | Insert that suggestion |
| Click | Insert the clicked suggestion |
| `Esc` | Insert exactly what you typed, in Latin letters |
| `Delete` | Edit what you're typing |
| `.` `,` `?` and other punctuation | Insert the first suggestion, then the punctuation |
| `Tab` | Insert what you typed as English, and stay in Khmer |
| Tap `Shift` with nothing typed | Switch between Khmer and English. A small **ខ** / **EN** badge shows the mode |

**Tips**

- Spell words however you normally do. `knhom`, `knh` and `nh` all work for ខ្ញុំ.
- When the right answer isn't first, pick it with a number. Typer remembers it and ranks it higher next time.
- For one English word in a Khmer sentence, type it and press `Tab`. It goes in exactly as typed, and you stay in Khmer.
- To type a lot of English, tap `Shift` with nothing typed. Your keys then go straight through as normal English. Tap `Shift` again to go back to Khmer. Holding `Shift` to type a capital letter does not switch modes.

## Install on Windows

1. Download **[Typer-windows-setup.exe](https://github.com/Nel-sokchhunly/typer/releases/latest/download/Typer-windows-setup.exe)** and double-click it.
2. If Windows shows *"Windows protected your PC"*, click **More info → Run anyway**. Typer isn't signed with a paid certificate yet.
3. Click **Install**, then **Finish**.
4. Press **`Windows` + `Space`** and choose **Typer សរសេរ**.

The keys are the same as on the Mac (see the table above). Picking with the mouse isn't supported on Windows yet; use `Enter` or `1` to `9`.
What you pick is saved in `%APPDATA%\Typer`. To uninstall, use **Settings → Apps → Installed apps → Typer**.

## Privacy

Everything stays on your Mac. Typer has no network access and sends nothing anywhere.

What you pick is saved locally so Typer can learn:

```
~/Library/Application Support/Typer/
  user.tsv    words and word pairs you've picked
  picks.tsv   what you typed → what you chose
```

Delete that folder at any time to reset what Typer has learned.

## Update

Run the install command from **step 1** again. What Typer has learned is kept. If it still behaves like the old version, switch to another input source and back, or log out and back in.

## Uninstall

1. Remove Typer from **System Settings → Keyboard → Input Sources**.
2. Run this in Terminal:

```sh
rm -rf ~/Library/Input\ Methods/Typer.app ~/Library/Application\ Support/Typer
```

## Problems?

- **No suggestions appear:** make sure Typer is the selected input source (check the menu bar). You may be in English mode; tap `Shift` once.
- **"Typer can't be opened" or nothing happens:** run the `xattr` line from step 1 again, then log out and back in.
- **Old icon in the Globe switcher or menu bar:** run `killall -9 TextInputSwitcher TextInputMenuAgent` in Terminal (macOS restarts them), or log out and back in.
- **Bad suggestion:** please report what you typed and what you expected at <https://github.com/Nel-sokchhunly/typer/issues>. These reports are how the engine improves.

## Development

Sing Khmer input engine: `knhom tov sala rean` → `ខ្ញុំទៅសាលារៀន`.

```
python3 data/build.py                                  # raw sources -> data/out/{lexicon,ngrams}.tsv
cd engine && cargo test --release                      # unit + real-data check
cd .. && engine/target/release/typer "knhom tov sala rean"
engine/target/release/typer                            # REPL; type a number after a phrase to pick/learn it
engine/target/release/typer eval eval/test.tsv         # top-1 / top-3 accuracy
```

Score per phrase = trigram LM (stupid backoff) − `SPELL_WEIGHT` × weighted edit distance(typed, spelling).
Tunables live at the top of `engine/src/lib.rs`.

User learning: picks append 1-3 gram counts to `$TYPER_USER/user.tsv` (default `data/user/`, boosted ×100 over corpus counts)
and log `typed<TAB>chosen` to `picks.tsv`. C ABI for frontends: `engine/typer.h`.

### macOS input method

```
macos/build.sh install     # build build/Typer.app for this Mac, copy to ~/Library/Input Methods
macos/build.sh dist        # universal build/Typer-macos.zip (local check; CI builds releases)
```
Release: `git tag v0.1.1 && git push origin v0.1.1`. CI (`.github/workflows/ci.yml`) tests, builds the macOS pkg + zip and the Windows installer, and publishes the GitHub release.

Then System Settings → Keyboard → Input Sources → Edit → + → Khmer → **Typer សរសេរ**. Switch with Ctrl-Space / Globe.

Type `knhom tov sala rean`: ↓/↑ = move highlight, Enter = insert highlighted, 1-9 = pick, Tab/Esc = keep latin, Delete = edit,
tap Shift alone (nothing typed) = toggle English passthrough.
Picks are learned into `~/Library/Application Support/Typer/` (`user.tsv`, `picks.tsv`).
After a rebuild, `install` restarts the input method; if it still looks stale, switch input source away and back.

### Windows input method

`windows/` is a TSF text service (COM DLL, Rust + `windows` crate) over the same engine; `windows/installer.iss` is the Inno Setup wizard.
CI builds the x64 + x86 DLLs on every push and, on tags, `Typer-windows-setup.exe` for the release.
From a Mac you can type-check it: `rustup target add x86_64-pc-windows-msvc && cargo check --manifest-path windows/Cargo.toml --target x86_64-pc-windows-msvc`.

### Data credits

- `data/raw/mobile-keyboard-data.json`: shared open Khmer/English keyboard n-gram data.
- `data/raw/hand-romans.txt`: from [khmer-text-transliteration](https://github.com/Chhunneng/khmer-text-transliteration),
  MIT License, Copyright (c) 2025 Chrea Chanchhunneng.
