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
