"""Turn Unicode's emoji-test.txt + CLDR English annotations into out/emoji.json for the iOS emoji keyboard.

out/emoji.json  [{"group": "Smileys & Emotion", "emoji": [{"e": "😀", "v": "1.0", "n": "grinning face",
                 "k": ["face", "grin", ...], "t": ["👋🏻", ... 5 tones light to dark]}, ...]}, ...]
Groups in Unicode order. "t" only when the emoji has skin tones; "k" only when CLDR has keywords.

Fully-qualified emoji only, "Component" group skipped. Skin-tone variants are attached to their base
emoji ("t"), never top-level; mixed-tone sequences (two people, different tones) are dropped.
Sources (pinned): raw/emoji-test.txt (Unicode 16.0); raw/cldr-annotations-en.xml and
raw/cldr-annotations-derived-en.xml from unicode-org/cldr tag release-46 (CLDR 46 covers Emoji 16.0),
common/annotations/en.xml and common/annotationsDerived/en.xml. Name falls back to emoji-test.txt.

Run: python3 data/emoji.py [--check]
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE / "raw" / "emoji-test.txt"
CLDR = [HERE / "raw" / "cldr-annotations-en.xml", HERE / "raw" / "cldr-annotations-derived-en.xml"]
OUT = HERE / "out" / "emoji.json"
TONES = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]
ANNOTATION = re.compile(r'<annotation cp="([^"]+)"( type="tts")?>([^<]*)</annotation>')


def key(s):
    return s.replace("️", "")


def cldr():
    """{emoji without FE0F: [name, keywords]}"""
    out = {}
    for path in CLDR:
        for cp, tts, text in ANNOTATION.findall(path.read_text(encoding="utf-8")):
            entry = out.setdefault(key(cp), [None, []])
            if tts:
                entry[0] = text
            else:
                entry[1] = [k.strip() for k in text.split("|") if k.strip()]
    return out


def parse(text):
    names = cldr()
    groups = []
    toned = []  # (base, tone index, emoji)
    for line in text.splitlines():
        if line.startswith("# group:"):
            groups.append({"group": line[8:].strip(), "emoji": []})
        elif line and not line.startswith("#"):
            codes, rest = line.split(";", 1)
            status, comment = rest.split("#", 1)
            if status.strip() != "fully-qualified":
                continue
            cps = [int(c, 16) for c in codes.split()]
            _, version, name = comment.split(None, 2)
            mods = {c for c in cps if c in TONES}
            if mods:
                if len(mods) == 1:  # matching tones only
                    base = "".join(chr(c) for c in cps if c not in TONES)
                    toned.append((base, TONES.index(mods.pop()), "".join(map(chr, cps))))
                continue
            e = "".join(map(chr, cps))
            cn, ck = names.get(key(e), [None, []])
            item = {"e": e, "v": version[1:], "n": cn or name.strip()}
            if ck:
                item["k"] = ck
            groups[-1]["emoji"].append(item)
    by_base = {}
    for g in groups:
        for item in g["emoji"]:
            by_base[key(item["e"])] = item
    parse.toned = len(toned)
    for base, i, e in toned:
        item = by_base.get(key(base))  # FE0F-insensitive: 🕵️‍♂️ is stored with it, its toned forms have none
        if item:
            item.setdefault("t", [None] * 5)[i] = e
        else:
            raise AssertionError(f"toned emoji without a base: {e}")
    return [g for g in groups if g["group"] != "Component"]


def check(groups):
    items = [i for g in groups for i in g["emoji"]]
    allemoji = [i["e"] for i in items]
    by = dict(zip(allemoji, items))
    assert len(groups) > 5, len(groups)
    assert groups[0]["emoji"][0]["e"] == "😀", groups[0]["group"]
    assert all(g["group"] != "Component" for g in groups)
    assert len(allemoji) == len(set(allemoji)), "duplicate emoji"
    assert all(g["emoji"] for g in groups), "empty group"
    assert all(re.fullmatch(r"\d+\.\d+", i["v"]) for i in items), "missing version"
    assert all(i["n"] for i in items), "missing name"
    for i in items:
        assert not any(ord(c) in TONES for c in i["e"]), f"toned top-level {i['e']}"
        if "t" in i:
            assert len(i["t"]) == 5 and all(i["t"]), f"incomplete tones {i['e']}"
    assert sum(len(i["t"]) for i in items if "t" in i) == parse.toned, "dropped tones"
    assert len(by["👍"]["t"]) == 5
    assert len(by["🤝"]["t"]) == 5
    assert by["😀"].get("k"), "no keywords"
    assert "pizza" in by["🍕"]["n"] or "pizza" in by["🍕"].get("k", []), by["🍕"]


if __name__ == "__main__":
    groups = parse(SRC.read_text(encoding="utf-8"))
    check(groups)
    if "--check" not in sys.argv:
        OUT.parent.mkdir(exist_ok=True)
        OUT.write_text(json.dumps(groups, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    items = [i for g in groups for i in g["emoji"]]
    print(f"ok: {len(groups)} groups, {len(items)} emoji, {sum('t' in i for i in items)} with tones")
