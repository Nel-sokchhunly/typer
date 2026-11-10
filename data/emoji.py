"""Turn Unicode's emoji-test.txt into out/emoji.json for the iOS emoji keyboard.

out/emoji.json  [["Smileys & Emotion", ["😀", "😃", ...]], ...]   [group, [emoji, ...]] pairs in Unicode order

Fully-qualified emoji only, "Component" group skipped. Skin-tone variants are dropped (base emoji only;
long-press tones come later). Source: raw/emoji-test.txt (Unicode 16.0, pinned).

Run: python3 data/emoji.py [--check]
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE / "raw" / "emoji-test.txt"
OUT = HERE / "out" / "emoji.json"
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


def check(groups):
    allemoji = [e for _, es in groups for e in es]
    assert len(groups) > 5, len(groups)
    assert "😀" in groups[0][1], groups[0][0]
    assert all(g != "Component" for g, _ in groups)
    assert len(allemoji) == len(set(allemoji)), "duplicate emoji"
    assert all(es for _, es in groups), "empty group"


if __name__ == "__main__":
    groups = parse(SRC.read_text(encoding="utf-8"))
    check(groups)
    if "--check" not in sys.argv:
        OUT.parent.mkdir(exist_ok=True)
        OUT.write_text(json.dumps(groups, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"ok: {len(groups)} groups, {sum(len(es) for _, es in groups)} emoji")
