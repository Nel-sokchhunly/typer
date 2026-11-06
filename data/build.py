"""Merge raw sources into engine inputs.

out/lexicon.tsv  khmer_word<TAB>roman1,roman2,...   (spelling data)
out/ngrams.tsv   n<TAB>w1 w2 w3<TAB>count            (Khmer language model, n=1..3)
out/english.tsv  w1 [w2]<TAB>count                    (English 1-2 grams, for English words typed in Khmer mode)
out/generated.tsv  same as lexicon.tsv, for words whose spellings are rule-generated (can be switched off)

Words with no recorded spelling (data/raw/words.txt, one Khmer word per line) get rule-based
spellings from romanize.py.

Run: python3 data/build.py
"""
import json
import re
from collections import defaultdict
from pathlib import Path

from romanize import romanize

HERE = Path(__file__).parent
RAW = HERE / "raw"
OUT = HERE / "out"
NON_KHMER = re.compile(r"[^ក-៿᧠-᧿]")  # drops ZWSP, punctuation, latin
MARKERS = {"<s>", "<oth>", "<unk>"}


def clean_word(w):
    return w if w in MARKERS else NON_KHMER.sub("", w)


def clean_roman(r):
    r = r.strip()
    if r != r.lower():  # "Costa Rica", "United States": English names, not typing
        return ""
    r = r.replace("'", "").replace("’", "")  # k'nhom == knhom; engine strips input the same way
    r = r.replace(" ", "")  # "pirn ng" (one word typed as two tokens): engine matches joined tokens
    return r if re.fullmatch(r"[a-z0-9]+", r) else ""


def build():
    romans = defaultdict(set)
    ngrams = defaultdict(int)
    english = defaultdict(int)

    for x in json.load(open(RAW / "mobile-keyboard-data.json", encoding="utf-8")):
        if x["lang"] != 0:
            w = x["word"].lower().replace("'", "").replace("’", "")  # don't == dont, as the engine normalizes
            if x["lang"] == 1 and x["gram"] <= 2 and re.fullmatch(r"[a-z]+( [a-z]+)?", w):
                english[w] += x["count"]
            continue
        words = [clean_word(w) for w in x["word"].split(" ")]
        if not all(words):
            continue
        ngrams[(len(words), " ".join(words))] += x["count"]
        if x["gram"] == 1:
            romans[words[0]].update(filter(None, map(clean_roman, x["oth"])))

    # old dataset "ខ្មែរ: a, b", hand-written + user-reported "ខ្មែរ=a,b": add chat spellings
    for path, sep in [(RAW / "old-dataset.txt", ":"), (RAW / "hand-romans.txt", "="), (RAW / "user-romans.txt", "=")]:
        for line in open(path, encoding="utf-8"):
            khmer, _, rs = line.partition(sep)
            khmer = clean_word(khmer.strip())
            rs = set(filter(None, map(clean_roman, rs.split(","))))
            if khmer and rs:
                romans[khmer] |= rs
                ngrams.setdefault((1, khmer), 1)  # unseen in corpus: minimal count

    # ្ត and ្ដ (subscript ta/da) look alike and sources mix them: ម្តាយ (old dataset) vs ម្ដាយ (corpus).
    # Fold each twin into whichever spelling the corpus uses more.
    twin = lambda w: w.replace("្ត", "\0").replace("្ដ", "្ត").replace("\0", "្ដ")
    for w in list(romans):
        t = twin(w)
        if t != w and t in romans and ngrams.get((1, t), 0) > ngrams.get((1, w), 0):
            romans[t] |= romans.pop(w)
            ngrams[(1, t)] += ngrams.pop((1, w), 0)

    # Khmer words with no recorded spelling (raw/words.txt, n-gram-only words): rule-based spellings.
    # Lowest priority: count 1, and never a spelling that is already real for another word, so
    # dataset words keep winning exact matches.
    real = {r for v in romans.values() for r in v}
    unspelled = {clean_word(l.strip()) for l in open(RAW / "words.txt", encoding="utf-8")}
    unspelled |= {w for (_, ws) in ngrams for w in ws.split(" ") if w not in MARKERS}
    generated = {}
    for w in unspelled - {k for k, v in romans.items() if v} - {""}:
        if re.search("[។៕៖ៗ៘៙៚]", w):  # punctuation, not a word (។ល។ = etc.)
            continue
        rs = [r for r in romanize(w) if r not in real]
        if rs:
            generated[w] = rs
            romans[w] = set(rs)
            ngrams.setdefault((1, w), 1)

    romans = {k: v for k, v in romans.items() if v}
    OUT.mkdir(exist_ok=True)
    # generated spellings go in their own file, so the engine can switch them off
    for name, keep in [("lexicon.tsv", lambda k: k not in generated), ("generated.tsv", lambda k: k in generated)]:
        with open(OUT / name, "w", encoding="utf-8") as f:
            for k in sorted(filter(keep, romans), key=lambda k: -ngrams.get((1, k), 0)):
                f.write(f"{k}\t{','.join(sorted(romans[k]))}\n")
    with open(OUT / "ngrams.tsv", "w", encoding="utf-8") as f:
        for (n, ws), c in sorted(ngrams.items(), key=lambda t: (t[0][0], -t[1])):
            f.write(f"{n}\t{ws}\t{c}\n")
    with open(OUT / "english.tsv", "w", encoding="utf-8") as f:
        for w, c in sorted(english.items(), key=lambda t: -t[1]):
            f.write(f"{w}\t{c}\n")
    return romans, ngrams, english, generated


if __name__ == "__main__":
    romans, ngrams, english, generated = build()
    # self-check: known words survive with chat spellings, junk is gone
    assert {"knhom", "knh", "nh"} <= romans["ខ្ញុំ"], romans["ខ្ញុំ"]
    assert {"sala", "sla"} <= romans["សាលា"]
    assert "hz" in romans["ហើយ"]
    assert ngrams[(2, "សាលា រៀន")] >= 460
    assert not any(NON_KHMER.search(k) for k in romans)
    assert not any(r in ("unitedstates", "costarica") for v in romans.values() for r in v)
    assert "ម្តាយ" not in romans and "ម្ដាយ" in romans  # twin folded into corpus spelling
    assert english["hello"] > 10000 and english["dont"] > 0 and english["thank you"] > 0 and "<s>" not in english
    assert "zin" in romans["ហ្សីន"]  # hand spelling kept
    assert generated and "kh" not in {r for v in generated.values() for r in v}  # real spellings never reused
    by_n = defaultdict(int)
    for n, _ in ngrams:
        by_n[n] += 1
    print(f"lexicon: {len(romans)} words, {sum(map(len, romans.values()))} spellings")
    print(f"ngrams: {dict(by_n)}")
    print(f"generated: {len(generated)} words")  # no Khmer: Windows consoles are cp1252
    print(f"english: {sum(' ' not in w for w in english)} words, {sum(' ' in w for w in english)} bigrams")
