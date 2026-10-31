# typer

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

## macOS input method

**Just want to use it?** See [INSTALL.md](INSTALL.md).

```
macos/build.sh install     # build build/Typer.app for this Mac, copy to ~/Library/Input Methods
macos/build.sh dist        # universal build/Typer-macos.zip for sharing (attach to a GitHub release)
```
Then System Settings → Keyboard → Input Sources → Edit → + → Khmer → **Typer**. Switch with Ctrl-Space / Globe.

Type `knhom tov sala rean`: Enter = top suggestion, 1-9 = pick, Esc = keep latin, Delete = edit.
Picks are learned into `~/Library/Application Support/Typer/` (`user.tsv`, `picks.tsv`).
After a rebuild, `install` restarts the input method; if it still looks stale, switch input source away and back.
