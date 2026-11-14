#!/bin/sh
# android/e2e.sh [scenario ...]    end-to-end tests of the Keyboard on a running emulator or device
#
# Installs the debug APK, enables and selects the Typer Keyboard (adb shell ime enable / ime set), opens the
# Companion app's try-it field and types with real taps on the real keys.
#
# How keys are found: every key, strip slot and panel row of the Keyboard is an accessibility node (TalkBack
# reads the same nodes) whose bounds come from the Keyboard's own layout code (core/KeyLayout.kt) placed in the
# input-method window. `uiautomator dump --windows` lists them with their on-screen bounds; the script taps the
# centre of the node with the wanted label ("k", "space", "delete", "ខ្ញុំ", ...). So the test taps where the
# Keyboard draws, at any screen size, without a copy of the layout maths.
#
# Each run leaves build/android/e2e/<timestamp>/: result.txt, a screenshot per scenario and logcat.txt.
# SKIP_BUILD=1 skips android/build.sh.
set -eu
cd "$(dirname "$0")/.."
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
PKG=com.chhunly.typer
IME=$PKG/.ime.TyperIME
APK=android/app/build/outputs/apk/debug/app-debug.apk
OUT="build/android/e2e/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
RESULT="$OUT/result.txt"
FAILED=0

[ "${SKIP_BUILD:-}" = 1 ] || sh android/build.sh >/dev/null
"$ADB" wait-for-device
"$ADB" install -r "$APK" >/dev/null
"$ADB" shell ime enable "$IME" >/dev/null
"$ADB" shell ime set "$IME" >/dev/null
"$ADB" logcat -c

log() { echo "$*" | tee -a "$RESULT"; }

# ui <command> [args]: reads the current window dump (all windows, so the Keyboard's too).
#   ui bounds <label>     centre "x y" of the node whose content-desc (or text, or resource-id) is <label>
#   ui text <resource-id> text of that node
#   ui labels             every Keyboard label, one per line
dump() { "$ADB" shell uiautomator dump --windows /sdcard/typer-ui.xml >/dev/null 2>&1; "$ADB" shell cat /sdcard/typer-ui.xml; }
ui() {
    dump >"$OUT/ui.xml"
    python3 - "$OUT/ui.xml" "$@" <<'PY'
import re, sys, xml.etree.ElementTree as ET
path, cmd, *args = sys.argv[1:]
raw = open(path, encoding="utf-8").read()
start = raw.find("<?xml")
docs = [d for d in re.split(r"(?=<\?xml)", raw[start:]) if d.strip()]
nodes = []
for d in docs:
    d = d[: d.rfind(">") + 1]
    try:
        root = ET.fromstring(d)
    except ET.ParseError:
        continue
    nodes += list(root.iter("node"))
def centre(n):
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", n.get("bounds")))
    return f"{(x1 + x2) // 2} {(y1 + y2) // 2}"
if cmd == "bounds":
    want = args[0]
    for key in ("content-desc", "text", "resource-id"):
        hit = [n for n in nodes if n.get(key) == want and (key != "content-desc" or n.get("package") == "com.chhunly.typer")]
        if hit:
            print(centre(hit[-1])); sys.exit(0)
    sys.exit(1)
if cmd == "text":
    hit = [n for n in nodes if n.get("resource-id") == args[0]]
    print(hit[0].get("text") if hit else ""); sys.exit(0 if hit else 1)
if cmd == "first":  # the strip's first slot: the first node after the Keyboard's own node
    labels = [n.get("content-desc") for n in nodes if n.get("package") == "com.chhunly.typer" and n.get("content-desc")]
    if "Typer keyboard" in labels:
        i = labels.index("Typer keyboard")
        if i + 1 < len(labels):
            print(labels[i + 1]); sys.exit(0)
    sys.exit(1)
if cmd == "rect":
    hit = [n for n in nodes if n.get("content-desc") == args[0]]
    if hit:
        print(*re.findall(r"\d+", hit[-1].get("bounds"))); sys.exit(0)
    sys.exit(1)
if cmd == "prefix":  # centre of the first Keyboard node whose label starts with this
    hit = [n for n in nodes if n.get("package") == "com.chhunly.typer" and (n.get("content-desc") or "").startswith(args[0])]
    if hit:
        print(centre(hit[0])); sys.exit(0)
    sys.exit(1)
if cmd == "desctext":  # text of the field (not a Keyboard key) with this content-desc
    hit = [n for n in nodes if n.get("content-desc") == args[0] and n.get("class") != "android.widget.Button"]
    print(hit[0].get("text") if hit else ""); sys.exit(0 if hit else 1)
if cmd == "labels":
    for n in nodes:
        if n.get("package") == "com.chhunly.typer" and n.get("content-desc"):
            print(n.get("content-desc"))
PY
}

# Key positions are read once per page (they don't move while typing on one page).
KEYS=""
read_keys() { dump >"$OUT/keys.xml"; KEYS="$OUT/keys.xml"; }
key_at() {
    python3 - "$KEYS" "$1" <<'PY'
import re, sys, xml.etree.ElementTree as ET
raw = open(sys.argv[1], encoding="utf-8").read()
for d in re.split(r"(?=<\?xml)", raw[raw.find("<?xml"):]):
    d = d[: d.rfind(">") + 1]
    if not d.strip():
        continue
    try:
        root = ET.fromstring(d)
    except ET.ParseError:
        continue
    for n in root.iter("node"):
        if n.get("package") == "com.chhunly.typer" and n.get("content-desc") == sys.argv[2]:
            x1, y1, x2, y2 = map(int, re.findall(r"\d+", n.get("bounds")))
            print((x1 + x2) // 2, (y1 + y2) // 2); sys.exit(0)
sys.exit(1)
PY
}
tap() { [ $# -eq 2 ] || { log "  nothing to tap"; return 1; }; "$ADB" shell input tap "$1" "$2"; }

# The return key's label is the field's action (return, next, go, search, send, done, previous).
return_key() {
    for l in return next go search send done previous; do key_at $l && return 0; done
    return 1
}

# type_keys "knhom tov": one real tap per character on the Keyboard's own key
type_keys() {
    s="$1"
    while [ -n "$s" ]; do
        c=$(printf '%s' "$s" | cut -c1)
        s=$(printf '%s' "$s" | cut -c2-)
        [ "$c" = " " ] && label=space || label="$c"
        xy=$(key_at "$label") || { log "  no key '$label' on screen"; return 1; }
        tap $xy
    done
}

# wait_for <label> [tries]: until a node with that label exists; prints its centre
wait_for() {
    i=0
    while [ $i -lt "${2:-20}" ]; do
        if xy=$(ui bounds "$1"); then echo "$xy"; return 0; fi
        i=$((i + 1))
        sleep 0.3
    done
    return 1
}

field_text() { ui text try; }

# No force-stop: the Keyboard lives in the same package, and stopping it makes Android fall back to another one.
open_app() {
    "$ADB" shell ime set "$IME" >/dev/null
    "$ADB" shell am start -W -f 0x10008000 -n $PKG/.app.MainActivity >/dev/null  # NEW_TASK | CLEAR_TASK: a fresh, empty field
    xy=$(wait_for try 30) || { log "  try-it field not found"; return 1; }
    n=0
    until tap $xy && wait_for space 8 >/dev/null; do  # a cold debug start can drop the first tap
        n=$((n + 1))
        [ $n -lt 4 ] || { log "  Keyboard did not open"; return 1; }
    done
    read_keys
}

check() { # check <name> <expected substring> <actual>
    if printf '%s' "$3" | grep -qF -- "$2"; then log "PASS $1: '$3'"; else log "FAIL $1: wanted '$2' in '$3'"; FAILED=1; fi
}

shot() { "$ADB" exec-out screencap -p >"$OUT/$1.png"; }

picks() { "$ADB" shell run-as $PKG cat files/user/picks.tsv 2>/dev/null || true; }

# Kill the Keyboard's process and select it again: a fresh engine that reloads Learning from disk.
restart_keyboard() {
    "$ADB" shell am force-stop $PKG
    "$ADB" shell ime set "$IME" >/dev/null
}

open_fields() { # the debug fields screen; tap the field with this label
    "$ADB" shell ime set "$IME" >/dev/null
    "$ADB" shell am start -W -f 0x10008000 -n $PKG/.FieldsActivity >/dev/null
    xy=$(wait_for "$1" 30) || { log "  field $1 not found"; return 1; }
    n=0
    until tap $xy && wait_for space 8 >/dev/null; do
        n=$((n + 1))
        [ $n -lt 4 ] || { log "  Keyboard did not open"; return 1; }
    done
    read_keys
}

# ---- scenarios ----

scenario_tracer() { # type knhom with real taps, tap the Suggestion, the field holds ខ្ញុំ
    open_app || { FAILED=1; return; }
    type_keys knhom
    xy=$(wait_for "ខ្ញុំ" 30) || { log "FAIL tracer: no ខ្ញុំ Suggestion; strip: $(ui labels | head -5 | tr '\n' '|')"; FAILED=1; shot tracer; return; }
    shot tracer-strip
    tap $xy
    sleep 0.5
    check tracer "ខ្ញុំ" "$(field_text)"
    shot tracer
}

scenario_phrase() { # a whole Phrase, committed by return: knhom tov sala rean -> ខ្ញុំទៅសាលារៀន
    open_app || { FAILED=1; return; }
    type_keys "knhom tov sala rean"
    wait_for "ខ្ញុំទៅសាលារៀន" 30 >/dev/null || log "  (Suggestion not shown yet; return computes it)"
    shot phrase-strip
    tap $(return_key)
    sleep 0.5
    check phrase "ខ្ញុំទៅសាលារៀន" "$(field_text)"
    shot phrase
}

scenario_learn() { # Pick a non-first Suggestion from the panel; after a Keyboard restart it ranks first
    "$ADB" shell run-as $PKG rm -f files/user/picks.tsv files/user/user.tsv
    restart_keyboard
    open_app || { FAILED=1; return; }
    type_keys "ah ach"
    sleep 1.5
    first=$(ui first)
    log "  before: first Suggestion '$first'"
    [ "$first" != "អាអាចម៍" ] || { log "FAIL learn: អាអាចម៍ already first before any Pick"; FAILED=1; return; }
    tap $(ui prefix "all suggestions") || { FAILED=1; return; }
    sleep 0.5
    set -- $(ui rect "Typer keyboard")
    n=0
    until xy=$(ui bounds "អាអាចម៍"); do  # the panel shows four rows at a time: scroll it like a finger would
        n=$((n + 1))
        [ $n -lt 4 ] || { log "FAIL learn: អាអាចម៍ not in the panel"; FAILED=1; shot learn; return; }
        "$ADB" shell input swipe 540 $(($4 - 120)) 540 $(($2 + 260)) 400
        sleep 0.4
    done
    shot learn-panel
    tap $xy
    sleep 0.5
    check "learn: picked" "អាអាចម៍" "$(field_text)"
    check "learn: picks.tsv" "ah ach	អាអាចម៍" "$(picks)"
    restart_keyboard
    open_app || { FAILED=1; return; }
    type_keys "ah ach"
    sleep 1.5
    check "learn: after restart, first Suggestion" "អាអាចម៍" "$(ui first)"
    shot learn
    xy=$(ui bounds "abc, keep Latin") && tap $xy  # leave the field clean
}

scenario_password() { # a password field stays Latin and writes nothing to picks.tsv
    before=$(picks)
    open_fields password || { FAILED=1; return; }
    labels=$(ui labels | tr '\n' '|')
    check "password: mode" "English mode" "$labels"
    type_keys "knhom tov"
    tap $(return_key)
    sleep 0.5
    check "password: field" "knhom tov" "$(ui desctext 'password echo')"
    after=$(picks)
    if [ "$before" = "$after" ]; then log "PASS password: picks.tsv unchanged"; else log "FAIL password: picks.tsv changed"; FAILED=1; fi
    if ui labels | grep -q "[ក-៿]"; then log "FAIL password: Khmer shown in the strip"; FAILED=1; else log "PASS password: no Khmer in the strip"; fi
    shot password
}

scenario_english() { # English mode: type hel, tap the best word, the field holds that word and a space
    open_app || { FAILED=1; return; }
    tap $(key_at "Khmer mode")
    wait_for "English mode" 10 >/dev/null || { log "FAIL english: mode key did not switch"; FAILED=1; return; }
    read_keys
    type_keys hel
    sleep 0.5
    best=$(ui first)
    shot english-strip
    log "  strip: $(ui labels | sed -n '2,4p' | tr '\n' '|')"
    [ -n "$best" ] && [ "$best" != "“hel”" ] || { log "FAIL english: no word suggestion"; FAILED=1; return; }
    tap $(ui bounds "$best")
    sleep 0.5
    text=$(field_text)
    if [ "$text" = "$best " ]; then log "PASS english: '$text'"; else log "FAIL english: wanted '$best ' got '$text'"; FAILED=1; fi
    shot english
    tap $(key_at "English mode")  # back to Khmer mode for later scenarios
}

hold() { # hold <x> <y> <seconds> [shot name]: touch down, wait, (screenshot), lift
    "$ADB" shell input motionevent DOWN "$1" "$2"
    sleep "$3"
    [ -z "${4:-}" ] || shot "$4"
    "$ADB" shell input motionevent UP "$1" "$2"
}

scenario_keys() { # long-press digit, key preview, pages, shift and caps lock, space-bar caret drag, field modes
    open_fields search || { FAILED=1; return; }
    check "keys: return shows the field's action" "search" "$(ui labels | tr '\n' '|')"
    shot keys-search
    set -- $(key_at e); hold $1 $2 0 keys-preview  # the screenshot outlasts 300 ms: it ends as a long press, 3
    set -- $(key_at w); hold $1 $2 0.7 keys-longpress  # long press: the hint digit 2
    check "keys: long press types the hint digit" "32" "$(ui desctext search)"
    tap $(key_at "numbers and symbols"); sleep 0.4; read_keys
    shot keys-numbers
    tap $(key_at 5)
    tap $(key_at "more symbols"); sleep 0.4; read_keys
    shot keys-symbols
    tap $(key_at "€")
    tap $(key_at letters); sleep 0.4; read_keys
    check "keys: numbers and symbols pages" "325€" "$(ui desctext search)"

    open_fields url || { FAILED=1; return; }
    check "keys: URL field starts English" "English mode" "$(ui labels | tr '\n' '|')"
    type_keys abcd
    set -- $(key_at space)
    "$ADB" shell input motionevent DOWN $1 $2
    sleep 0.5  # hold: the caret follows the finger
    "$ADB" shell input motionevent MOVE $(($1 - 30)) $2
    "$ADB" shell input motionevent MOVE $(($1 - 60)) $2
    "$ADB" shell input motionevent UP $(($1 - 60)) $2
    type_keys x
    check "keys: space-bar drag moved the caret two left" "abxcd" "$(ui desctext url)"
    tap $(key_at shift); read_keys; type_keys A  # shift once: one capital, then off
    read_keys
    set -- $(key_at shift); "$ADB" shell "input tap $1 $2; input tap $1 $2"; read_keys  # double tap: caps lock
    type_keys BC
    tap $(key_at "caps lock"); read_keys; type_keys d
    check "keys: shift once, caps lock, off (typed where the drag left the caret)" "abxABCdcd" "$(ui desctext url)"
    tap $(key_at "English mode"); sleep 0.4
    check "keys: a URL field can switch to Khmer" "Khmer mode" "$(ui labels | tr '\n' '|')"

    open_fields email || { FAILED=1; return; }
    tap $(key_at "English mode"); sleep 0.4
    check "keys: email stays English" "English mode" "$(ui labels | tr '\n' '|')"
    type_keys knhom
    check "keys: email types Latin" "knhom" "$(ui desctext email)"
}

# Screenshots of Typer in the same field the Gboard reference used (Contacts, First name; android/docs/reference.md),
# light and dark, at 411 and 360 dp wide, idle and composing. Not a pass/fail check: for comparing by eye.
scenario_compare() {
    for size in 1080x2400:420 720x1600:320; do
        "$ADB" shell wm size ${size%%:*}; "$ADB" shell wm density ${size##*:}
        for night in no yes; do
            "$ADB" shell cmd uimode night $night >/dev/null
            sleep 2
            "$ADB" shell ime set "$IME" >/dev/null
            "$ADB" shell am start -W -f 0x10008000 -a android.intent.action.INSERT -t vnd.android.cursor.dir/contact >/dev/null
            xy=$(wait_for "First name" 30) || { log "  no Contacts form"; continue; }
            n=0
            until tap $xy && wait_for space 8 >/dev/null; do n=$((n + 1)); [ $n -lt 4 ] || break; done
            name="typer-$([ $night = yes ] && echo dark || echo light)-${size%%x*}"
            shot "$name"
            read_keys
            type_keys knhom
            sleep 1
            shot "$name-strip"
            xy=$(ui bounds "abc, keep Latin") && tap $xy
            "$ADB" shell input keyevent KEYCODE_BACK
        done
    done
    "$ADB" shell wm size reset; "$ADB" shell wm density reset; "$ADB" shell cmd uimode night no >/dev/null
    log "PASS compare: screenshots saved"
}

log "Typer Android e2e $(date)  device: $("$ADB" shell getprop ro.product.model | tr -d '\r') API $("$ADB" shell getprop ro.build.version.sdk | tr -d '\r')"
for s in ${*:-tracer phrase learn password english keys}; do
    log "-- $s"
    "scenario_$s"
done
"$ADB" logcat -d >"$OUT/logcat.txt" 2>/dev/null || true
log "artifacts: $OUT"
[ $FAILED = 0 ] && log "ALL PASSED" || log "FAILED"
exit $FAILED
