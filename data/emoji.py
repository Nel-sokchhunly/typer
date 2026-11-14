"""Turn Unicode's emoji-test.txt into the emoji keyboards' data.

out/emoji.json           [["Smileys & Emotion", ["😀", "😃", ...]], ...]   [group, [emoji, ...]] pairs in Unicode order
out/emoji-variants.json  {"👋": ["👋🏻", "👋🏼", ...], ...}   skin-tone variants of each base emoji, Unicode order
out/emoji-names.tsv      emoji, English name, English keywords, Khmer name, Khmer keywords (for search; TalkBack)

Fully-qualified emoji only, "Component" group skipped. Skin-tone variants are dropped (base emoji only;
tones are in emoji-variants.json). Sources: raw/emoji-test.txt (Unicode 16.0, pinned) and the CLDR 46 emoji
annotations raw/cldr-annotations-{en,km}.xml and raw/cldr-annotations-derived-{en,km}.xml (flags and sequences),
Unicode License v3, matching Emoji 16.0. Keywords are " | " separated.

Run: python3 data/emoji.py [--check]
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE / "raw" / "emoji-test.txt"
OUT = HERE / "out" / "emoji.json"
VARIANTS = HERE / "out" / "emoji-variants.json"
NAMES = HERE / "out" / "emoji-names.tsv"
SKIN_TONES = {0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF}


def parse(text):
    groups = []
    for line in text.splitlines():
        if line.startswith("# group:"):
            groups.append([line[8:].strip(), []])
        elif line and not line.startswith("#"):
            codes, rest = line.split(";", 1)
            if rest.split("#")[0].strip() != "fully-qualified":
                continue
            cps = [int(c, 16) for c in codes.split()]
            if SKIN_TONES.intersection(cps):
                continue
            groups[-1][1].append("".join(map(chr, cps)))
    return [g for g in groups if g[0] != "Component"]


def variants(text):
    """Base emoji -> its skin-tone variants, in Unicode order (the tones follow their base in emoji-test.txt)."""
    out = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        codes, rest = line.split(";", 1)
        if rest.split("#")[0].strip() != "fully-qualified":
            continue
        cps = [int(c, 16) for c in codes.split()]
        if SKIN_TONES.intersection(cps):
            base = "".join(chr(c) for c in cps if c not in SKIN_TONES)
            out.setdefault(base, []).append("".join(map(chr, cps)))
    return out


def annotations(lang):
    """CLDR annotations: emoji (without U+FE0F) -> (name, keywords)."""
    import xml.etree.ElementTree as ET
    names, words = {}, {}
    roots = [ET.parse(HERE / "raw" / f).getroot() for f in (f"cldr-annotations-{lang}.xml", f"cldr-annotations-derived-{lang}.xml")]
    for a in (a for r in roots for a in r.iter("annotation")):
        cp = a.get("cp").replace("\ufe0f", "")
        if a.get("type") == "tts":
            names[cp] = a.text.strip()
        else:
            words[cp] = " | ".join(w.strip() for w in a.text.split("|"))
    return {cp: (names.get(cp, ""), words.get(cp, "")) for cp in set(names) | set(words)}


def name_rows(groups, tones):
    """Names for every emoji in the grid and every skin-tone variant (TalkBack reads "waving hand: medium skin tone")."""
    en, km = annotations("en"), annotations("km")
    rows = []
    for e in [e for _, es in groups for e in es] + [v for vs in tones.values() for v in vs]:
        k = e.replace("\ufe0f", "")
        (en_name, en_words), (km_name, km_words) = en.get(k, ("", "")), km.get(k, ("", ""))
        if en_name or km_name:
            rows.append("\t".join([e, en_name, en_words, km_name, km_words]))
    return rows


def check(groups):
    allemoji = [e for _, es in groups for e in es]
    assert len(groups) > 5, len(groups)
    assert "😀" in groups[0][1], groups[0][0]
    assert all(g != "Component" for g, _ in groups)
    assert len(allemoji) == len(set(allemoji)), "duplicate emoji"
    assert all(es for _, es in groups), "empty group"


if __name__ == "__main__":
    text = SRC.read_text(encoding="utf-8")
    groups = parse(text)
    check(groups)
    allemoji = {e for _, es in groups for e in es}
    # tone variants drop U+FE0F ("✌🏻" for "✌️"): key them by the grid's own spelling of the base
    canonical = {e.replace("\ufe0f", ""): e for e in allemoji}
    # two-person emoji take their tones as sequences; the grid shows the single-character form
    couples = {"🫱\u200d🫲": "🤝", "👩\u200d🤝\u200d👩": "👭", "👩\u200d🤝\u200d👨": "👫", "👨\u200d🤝\u200d👨": "👬",
               "🧑\u200d❤\u200d💋\u200d🧑": "💏", "🧑\u200d❤\u200d🧑": "💑"}
    tones = {}
    for b, v in variants(text).items():
        key = b.replace("\ufe0f", "")
        tones.setdefault(canonical.get(key) or couples.get(key, b), []).extend(v)
    assert tones and all(b in allemoji for b in tones), "a variant without its base"
    rows = name_rows(groups, tones)
    assert len(rows) > 0.9 * (len(allemoji) + sum(map(len, tones.values()))), f"names for only {len(rows)} emoji"
    if "--check" not in sys.argv:
        OUT.parent.mkdir(exist_ok=True)
        OUT.write_text(json.dumps(groups, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        VARIANTS.write_text(json.dumps(tones, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        NAMES.write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(f"ok: {len(groups)} groups, {len(allemoji)} emoji, {len(tones)} with skin tones, {len(rows)} named")
