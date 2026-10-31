"""Merge raw sources into engine inputs.

out/lexicon.tsv  khmer_word<TAB>roman1,roman2,...   (spelling data)
out/ngrams.tsv   n<TAB>w1 w2 w3<TAB>count            (Khmer language model, n=1..3)

Run: python3 data/build.py
"""
import json
import re
from collections import defaultdict
from pathlib import Path

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
    return r if re.fullmatch(r"[a-z0-9]+", r) else ""


def build():
    romans = defaultdict(set)
    ngrams = defaultdict(int)

    for x in json.load(open(RAW / "mobile-keyboard-data.json", encoding="utf-8")):
        if x["lang"] != 0:  # ponytail: Khmer only, English passthrough until bilingual matters
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

    romans = {k: v for k, v in romans.items() if v}
    OUT.mkdir(exist_ok=True)
    with open(OUT / "lexicon.tsv", "w", encoding="utf-8") as f:
        for k in sorted(romans, key=lambda k: -ngrams.get((1, k), 0)):
            f.write(f"{k}\t{','.join(sorted(romans[k]))}\n")
    with open(OUT / "ngrams.tsv", "w", encoding="utf-8") as f:
        for (n, ws), c in sorted(ngrams.items(), key=lambda t: (t[0][0], -t[1])):
            f.write(f"{n}\t{ws}\t{c}\n")
    return romans, ngrams


if __name__ == "__main__":
    romans, ngrams = build()
    # self-check: known words survive with chat spellings, junk is gone
    assert {"knhom", "knh", "nh"} <= romans["ខ្ញុំ"], romans["ខ្ញុំ"]
    assert {"sala", "sla"} <= romans["សាលា"]
    assert "hz" in romans["ហើយ"]
    assert ngrams[(2, "សាលា រៀន")] >= 460
    assert not any(NON_KHMER.search(k) for k in romans)
    assert not any(r in ("unitedstates", "costarica") for v in romans.values() for r in v)
    by_n = defaultdict(int)
    for n, _ in ngrams:
        by_n[n] += 1
    print(f"lexicon: {len(romans)} words, {sum(map(len, romans.values()))} spellings")
    print(f"ngrams: {dict(by_n)}")
