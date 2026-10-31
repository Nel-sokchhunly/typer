# Install Typer on macOS

Typer lets you type Khmer the way you already chat in Latin letters (Sing Khmer):

```
knhom tov sala rean   →   ខ្ញុំទៅសាលារៀន
anh ot jg tv teas te  →   អញអត់ចង់ទៅផ្ទះទេ
```

It works in any app: Messenger, Telegram, Notes, browsers, and so on.

**Requirements:** macOS 13 (Ventura) or newer, on an Apple Silicon or Intel Mac.

> Typer is an early preview. Expect wrong suggestions sometimes. It learns from what you pick, so it gets better the more you use it.

## 1. Download

Download **`Typer-macos.zip`** from the [Releases page](https://github.com/Nel-sokchhunly/typer/releases), or get it from whoever shared it with you.

## 2. Install

Open **Terminal** (press `⌘ Space`, type *Terminal*, press Enter), then paste these lines and press Enter:

```sh
cd ~/Downloads
unzip -o Typer-macos.zip
xattr -dr com.apple.quarantine Typer.app
mkdir -p ~/Library/Input\ Methods
rm -rf ~/Library/Input\ Methods/Typer.app
mv Typer.app ~/Library/Input\ Methods/
```

> **Why the `xattr` line?** Typer isn't signed with a paid Apple Developer certificate yet, so macOS blocks it by default when it comes from the internet. This line removes that block for Typer only. Only run it if you trust where you got the zip.

## 3. Turn it on

1. Open **System Settings → Keyboard**.
2. Under **Text Input**, click **Edit…** next to *Input Sources*.
3. Click **+** at the bottom left, choose **Khmer** in the list, select **Typer**, and click **Add**.

If Typer isn't in the list, **log out and log back in** (Apple menu → Log Out), then try again.

## 4. Use it

Switch to Typer with **`Ctrl Space`** or the **🌐 Globe** key. You can also pick it from the input menu in the menu bar.

Type Khmer in Latin letters, with spaces between words. A list of suggestions appears under your text.

| Key | What it does |
|---|---|
| `Enter` | Insert the first suggestion |
| `1` to `9` | Insert that suggestion |
| Click | Insert the clicked suggestion |
| `Esc` | Insert exactly what you typed, in Latin letters |
| `Delete` | Edit what you're typing |
| `.` `,` `?` and other punctuation | Insert the first suggestion, then the punctuation |

**Tips**

- Spell words however you normally do. `knhom`, `knh` and `nh` all work for ខ្ញុំ.
- When the right answer isn't first, pick it with a number. Typer remembers it and ranks it higher next time.
- To type English, switch back to your normal keyboard with `Ctrl Space`.

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

Download the new zip and repeat **step 2**. What Typer has learned is kept. If it still behaves like the old version, switch to another input source and back, or log out and back in.

## Uninstall

1. Remove Typer from **System Settings → Keyboard → Input Sources**.
2. Run this in Terminal:

```sh
rm -rf ~/Library/Input\ Methods/Typer.app ~/Library/Application\ Support/Typer
```

## Problems?

- **No suggestions appear:** make sure Typer is the selected input source (check the menu bar).
- **"Typer can't be opened" or nothing happens:** run the `xattr` line from step 2 again, then log out and back in.
- **Bad suggestion:** please report what you typed and what you expected at <https://github.com/Nel-sokchhunly/typer/issues>. These reports are how the engine improves.
