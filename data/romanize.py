"""Rule-based Khmer word -> chat romanizations, for words that have no recorded spelling.

romanize("ហ្សីន") -> ["zin", "zein", ...]  (most likely first)

Run: python3 -I data/romanize.py            # scores the rules against the corpus's real spellings
     python3 -I data/romanize.py ខ្មែរ ...   # show spellings for some words
"""
import itertools
import re

# consonant -> (spellings, series): series "a" or "o" decides how vowels sound
CONS = {
    "ក": (["k"], "a"), "ខ": (["kh", "k"], "a"), "គ": (["k", "g"], "o"), "ឃ": (["kh", "k"], "o"),
    "ង": (["ng"], "o"), "ច": (["ch", "j", "c"], "a"), "ឆ": (["chh", "ch"], "a"), "ជ": (["ch", "j"], "o"),
    "ឈ": (["chh", "ch"], "o"), "ញ": (["nh"], "o"), "ដ": (["d"], "a"), "ឋ": (["th", "t"], "a"),
    "ឌ": (["d"], "o"), "ឍ": (["th", "t"], "o"), "ណ": (["n"], "a"), "ត": (["t"], "a"),
    "ថ": (["th", "t"], "a"), "ទ": (["t"], "o"), "ធ": (["th", "t"], "o"), "ន": (["n"], "o"),
    "ប": (["b"], "a"), "ផ": (["ph", "p"], "a"), "ព": (["p", "ph"], "o"), "ភ": (["ph", "p"], "o"),
    "ម": (["m"], "o"), "យ": (["y"], "o"), "រ": (["r"], "o"), "ល": (["l"], "o"), "វ": (["v", "w"], "o"),
    "ស": (["s"], "a"), "ហ": (["h"], "a"), "ឡ": (["l"], "a"), "អ": ([""], "a"),
}
# ហ + subscript spells foreign sounds: ហ្ស = z, ហ្វ = f
H_CLUSTER = {"ស": ["z", "s"], "វ": ["f", "v"], "គ": ["g", "k"], "ន": ["n"], "ម": ["m"], "ល": ["l"], "យ": ["y"], "រ": ["r"]}
FINAL = {
    "ក": ["k"], "ខ": ["kh", "k"], "គ": ["k"], "ឃ": ["k"], "ង": ["ng"], "ច": ["ch", "c", "j"], "ញ": ["nh", "n"],
    "ដ": ["d", "t"], "ឌ": ["d"], "ត": ["t"], "ទ": ["t"], "ធ": ["t"], "ថ": ["t"], "ណ": ["n"], "ន": ["n"],
    "ប": ["b", "p"], "ព": ["p", "b"], "ផ": ["p"], "ភ": ["p"], "ម": ["m"], "យ": ["y", "i"], "រ": ["r", ""],
    "ល": ["l"], "វ": ["v", "w", "o"], "ស": ["s", "h"], "ហ": ["h"], "ឡ": ["l"], "ជ": ["ch", "j"], "ឆ": ["ch"],
    "ឈ": ["ch"], "ញ់": ["nh"],
}
# vowel sign(s) -> (a-series spellings, o-series spellings)
VOWELS = {
    "": (["a", "o", "or"], ["o", "or", "a"]),
    "ា": (["a", "ar", "aa"], ["ea", "a", "eia"]),
    "ិ": (["e", "i"], ["i", "e"]),
    "ី": (["ei", "i", "ey"], ["i", "ii", "ei"]),
    "ឹ": (["oe", "e", "eu"], ["ue", "eu", "e"]),
    "ឺ": (["eu", "ue"], ["ueu", "eu", "ue"]),
    "ុ": (["o", "u"], ["u", "o"]),
    "ូ": (["ou", "o", "u"], ["u", "ou", "o"]),
    "ួ": (["uo", "ou", "u"], ["uo", "ou", "u"]),
    "ើ": (["ae", "er", "aeu"], ["eu", "er", "au", "oe"]),
    "ឿ": (["oea", "eua"], ["oea", "eua", "ue"]),
    "ៀ": (["ie", "ea"], ["ie", "ea"]),
    "េ": (["e", "ei"], ["e", "ei"]),
    "ែ": (["ae", "e"], ["ae", "e"]),
    "ៃ": (["ai", "ay"], ["ey", "ai", "ei"]),
    "ោ": (["ao", "o"], ["o", "ou", "ao"]),
    "ៅ": (["av", "ao", "ov"], ["ov", "ou", "av"]),
    "ុំ": (["om", "um"], ["um", "om"]),
    "ំ": (["am", "om"], ["um", "om", "am"]),
    "ាំ": (["am"], ["oam", "eam", "am"]),
    "ះ": (["ah", "as", "a"], ["eah", "eas", "ea"]),
    "ុះ": (["oh", "os"], ["uh", "us", "oh"]),
    "េះ": (["eh", "es", "is"], ["eh", "is", "es"]),
    "ោះ": (["aoh", "oh", "os"], ["uoh", "us", "oh"]),
    "ិះ": (["eh", "is"], ["ih", "is", "eh"]),
    "ែះ": (["aeh", "eh"], ["aeh", "eh"]),
    "ៈ": (["a", "ak"], ["ea", "eak"]),
    "័": (["a"], ["oa", "o", "a"]),
}
SHORT = {"ea": "a", "oa": "o", "ou": "o", "ei": "i", "ae": "a", "ie": "e", "uo": "o", "eu": "o"}  # before ់
INDEPENDENT = {
    "ឥ": ["e", "i"], "ឦ": ["ei", "i"], "ឧ": ["o", "u"], "ឩ": ["ou", "u"], "ឪ": ["ov", "ou"],
    "ឫ": ["rue", "reu"], "ឬ": ["rue", "reu", "ru"], "ឭ": ["lue", "leu"], "ឮ": ["lue", "leu", "lu"],
    "ឯ": ["ae", "e"], "ឰ": ["ai"], "ឱ": ["ao", "o"], "ឲ": ["ao", "oy"], "ឳ": ["av", "ov"],
}
COENG, BANTOC, SILENT, ROBAT = "្", "់", "៍", "៌"
SERIES_MARKS = {"៊": "o", "៉": "a"}
VOWEL_CHARS = set("ាិីឹឺុូួើឿៀេែៃោៅំះៈ័")
MAX_OUT = 12


def clusters(word):
    """Split into written clusters: dict(cons=[c, sub, ...], vowel=str, bantoc, silent, indep)."""
    out, i, n = [], 0, len(word)
    while i < n:
        c = word[i]
        i += 1
        if c in INDEPENDENT:
            out.append(dict(cons=[], vowel="", bantoc=False, silent=False, indep=INDEPENDENT[c]))
            continue
        if c not in CONS:
            continue  # stray sign or punctuation
        k = dict(cons=[c], vowel="", bantoc=False, silent=False, indep=None, series=CONS[c][1])
        while i < n:
            ch = word[i]
            if ch == COENG and i + 1 < n and word[i + 1] in CONS:
                k["cons"].append(word[i + 1])
                i += 2
            elif ch in SERIES_MARKS:
                k["series"] = SERIES_MARKS[ch]
                i += 1
            elif ch in VOWEL_CHARS:
                k["vowel"] += ch
                i += 1
            elif ch == BANTOC:
                k["bantoc"] = True
                i += 1
            elif ch in (SILENT, ROBAT):
                k["silent"] = True
                i += 1
            else:
                break
        out.append(k)
    return out


def onset(k):
    cs = k["cons"]
    if cs[0] == "ហ" and len(cs) > 1 and cs[1] in H_CLUSTER:  # ហ្ស = z
        heads, cs = [H_CLUSTER[cs[1]]], cs[2:]
    elif cs[0] == "អ":  # អ is a glottal stop: អ្នក = anak / nak
        heads, cs = [["", "a"] if len(cs) > 1 else [""]], cs[1:]
    else:
        heads, cs = [CONS[cs[0]][0]], cs[1:]
    if k["series"] == "a" and cs and CONS[cs[-1]][1] == "o" and cs[-1] not in "ងញនមយរលវ":
        k["series"] = "o"  # a voiced subscript (ព, គ, ...) makes the cluster o-series
    parts = heads + [["", "a"] if c == "អ" else CONS[c][0] for c in cs]
    return ["".join(p) for p in itertools.product(*parts)]


def vowel(k):
    v = k["vowel"]
    if v not in VOWELS:  # unusual combo: spell its signs one by one
        return ["".join(p) for p in itertools.product(*(VOWELS.get(ch, ([""], [""]))[0] for ch in v))]
    a, o = VOWELS[v]
    return a if k["series"] == "a" else o


def parts(word):
    """Each written cluster becomes one part: a list of (spelling, cost), cheapest first."""
    ks = clusters(word)
    out = []
    for i, k in enumerate(ks):
        if k["indep"]:
            out.append([(s, r) for r, s in enumerate(k["indep"])])
            continue
        if k["silent"] and not k["vowel"]:
            continue  # ណ៍, ធ៌: not pronounced
        prev = ks[i - 1] if i else None
        nxt = ks[i + 1] if i + 1 < len(ks) else None
        bare = len(k["cons"]) == 1 and not k["vowel"]
        can_close = prev and not (prev["vowel"] and prev["vowel"][-1] in "ំះៈ" and k["cons"] != ["ង"]) and not prev.get("closed")
        doubled = not k["vowel"] and len(k["cons"]) == 2 and k["cons"][0] == k["cons"][1] and k["cons"][0] in FINAL
        if doubled and can_close:  # ចិត្ត = chet, កម្មករ = kam-mo-kor
            fin = [(s, r) for r, s in enumerate(FINAL[k["cons"][0]])]
            if nxt is None:
                out.append(fin)
            else:
                again = [(f + o + v, rf + ro + rv) for f, rf in fin for ro, o in enumerate(CONS[k["cons"][0]][0])
                         for rv, v in enumerate(["", "a", "o"])]
                out.append(again)
            k["closed"] = True
            continue
        if bare and k["cons"][0] in FINAL and can_close and k["bantoc"]:
            k["closed"] = True
            out[-1] = _shorten(out[-1])
            out.append([(s, r) for r, s in enumerate(FINAL[k["cons"][0]])])
            continue
        own = [(o + v, ro + rv) for ro, o in enumerate(onset(k)) for rv, v in enumerate(vowel(k))]
        if k["bantoc"]:
            own = _shorten(own)
        if bare and k["cons"][0] in FINAL and can_close and not (nxt and nxt["bantoc"]):
            # a lone consonant: closes the previous syllable (បាន = ban) or starts one (បុរស = bo-ros)
            final_first = nxt is None or bool(nxt["vowel"]) or len(nxt["cons"]) > 1 or bool(nxt["indep"])
            fin = [(s, r + (0 if final_first else 2)) for r, s in enumerate(FINAL[k["cons"][0]])]
            own = [(s, r + (2 if final_first else 0)) for s, r in own]
            k["closed"] = final_first
            out.append(fin + own)
        else:
            out.append(own)
    return out


def _shorten(opts):
    """Vowel before ់ is short: ចាប់ = chab, not cheab."""
    res = []
    for s, r in opts:
        res.append((s, r))
        for long, short in SHORT.items():
            if s.endswith(long):
                res.append((s[: -len(long)] + short, r))
    return res


def romanize(word, limit=MAX_OUT):
    ps = parts(word)
    if not ps:
        return []
    scored = {}
    for combo in itertools.islice(itertools.product(*ps), 50000):
        s = re.sub(r"m(ng)", r"\1", "".join(x for x, _ in combo))  # ាំង = ang, not amng
        cost = sum(r for _, r in combo)
        if s and cost < scored.get(s, 99):
            scored[s] = cost
    return sorted(scored, key=lambda s: (scored[s], len(s)))[:limit]


if __name__ == "__main__":
    import json
    import sys
    from pathlib import Path

    for w in sys.argv[1:]:
        print(w, romanize(w))
    if len(sys.argv) > 1:
        sys.exit()

    for w, want in [("ហ្សីន", "zin"), ("បាន", "ban"), ("របស់", "robos"), ("ខ្លាំង", "khlang"), ("អ្វី", "avei"),
                    ("បុរស", "boros"), ("ពិភព", "piphop"), ("ខ្ញុំ", "knhom"), ("ស្អាត", "saat")]:
        assert want in romanize(w), (w, want, romanize(w))

    raw = json.load(open(Path(__file__).parent / "raw" / "mobile-keyboard-data.json", encoding="utf-8"))
    words = [(x["word"], set(x["oth"]), x["count"]) for x in raw if x["lang"] == 0 and x["gram"] == 1 and x["oth"]]
    hit = top1 = whit = wtot = 0
    misses = []
    for w, real, count in words:
        got = romanize(w)
        ok = bool(set(got) & real)
        hit += ok
        top1 += bool(got) and got[0] in real
        whit += ok * count
        wtot += count
        if not ok and len(misses) < int(sys.argv[1] if len(sys.argv) > 1 else 30):
            misses.append((w, sorted(real), got[:5]))
    print(f"words: {len(words)}  any real spelling in top {MAX_OUT}: {100 * hit / len(words):.1f}%  "
          f"top1: {100 * top1 / len(words):.1f}%  count-weighted: {100 * whit / wtot:.1f}%")
    for m in misses:
        print("MISS", *m)
