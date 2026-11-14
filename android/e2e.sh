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
    hit = [n for n in nodes if n.get("content-desc") == args[0]
           and n.get("class") not in ("android.widget.Button", "android.inputmethodservice.Keyboard$Key")]
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
    _wi=0
    while [ $_wi -lt "${2:-20}" ]; do
        if _found=$(ui bounds "$1"); then echo "$_found"; return 0; fi  # not $xy or $i: callers keep theirs
        _wi=$((_wi + 1))
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
    select_keyboard
}

# Android falls back to another keyboard when ours is stopped; select Typer until it sticks.
select_keyboard() {
    i=0
    while [ $i -lt 10 ]; do
        "$ADB" shell ime set "$IME" >/dev/null
        sleep 0.5
        [ "$("$ADB" shell settings get secure default_input_method | tr -d '\r')" = "$IME" ] && return 0
        i=$((i + 1))
    done
    log "  could not select the Typer Keyboard"
    return 1
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
    set -- $(key_at e); hold $1 $2 0 keys-preview  # a tap ("e", a Phrase) or, if the screenshot is slow, a long press ("3")
    xy=$(ui bounds "abc, keep Latin") && tap $xy
    tap $(key_at delete)  # either way, the field is empty again
    set -- $(key_at w); hold $1 $2 0.7 keys-longpress  # long press: the hint digit 2
    check "keys: long press types the hint digit" "2" "$(ui desctext search)"
    tap $(key_at "numbers and symbols"); sleep 0.4; read_keys
    shot keys-numbers
    tap $(key_at 5)
    tap $(key_at "more symbols"); sleep 0.4; read_keys
    shot keys-symbols
    tap $(key_at "€")
    tap $(key_at letters); sleep 0.4; read_keys
    check "keys: numbers and symbols pages" "25€" "$(ui desctext search)"

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

scenario_companion() { # the Companion app: setup steps report Done, Open Settings works, light/dark, Khmer/English
    "$ADB" shell ime set "$IME" >/dev/null
    for night in no yes; do
        "$ADB" shell cmd uimode night $night >/dev/null
        sleep 1.5
        "$ADB" shell am start -W -f 0x10008000 -n $PKG/.app.MainActivity >/dev/null
        wait_for try 30 >/dev/null || { log "FAIL companion: no screen"; FAILED=1; return; }
        tap $(ui bounds "ភាសា ខ្មែរ" 2>/dev/null || ui bounds "ខ្មែរ") 2>/dev/null || true
        sleep 0.5
        shot "companion-khmer-$night"
        [ $night = no ] && check "companion: steps 1 and 2 done (Khmer)" "1, រួចរាល់|2, រួចរាល់" "$(ui labels | tr '\n' '|')"
        tap $(ui bounds EN)
        sleep 0.5
        shot "companion-english-$night"
        [ $night = no ] && check "companion: steps 1 and 2 done (English)" "1, Done|2, Done" "$(ui labels | tr '\n' '|')"
        "$ADB" shell input swipe 540 1800 540 500 300
        sleep 0.5
        shot "companion-english-$night-scrolled"
    done
    "$ADB" shell cmd uimode night no >/dev/null
    "$ADB" shell am start -W -f 0x10008000 -n $PKG/.app.MainActivity >/dev/null
    tap $(wait_for "Open Settings" 20)
    sleep 1.5
    check "companion: Open Settings opens the keyboard settings" "com.android.settings" "$("$ADB" shell dumpsys window | grep -m1 mCurrentFocus)"
    "$ADB" shell input keyevent KEYCODE_BACK
}

# ImeTracker (Android's own IME logging): ms from the app's first "onRequestShow" (the field took focus and asked for
# the keyboard) to the last "onShown" (the Keyboard's window is on screen with its first frame). The show itself is
# tracked under a system_server token, so the two are matched by time, after a logcat -c.
show_ms() {
    "$ADB" logcat -d -v epoch -s ImeTracker | python3 -c '
import re, sys
pkg = sys.argv[1]; start = shown = None
for line in sys.stdin:
    m = re.match(r"\s*([\d.]+)\s.*ImeTracker: (\S+?):\w+: (onRequestShow|onShown)", line)
    if not m: continue
    t, who, what = float(m.group(1)), m.group(2), m.group(3)
    if what == "onRequestShow" and who == pkg and start is None: start = t
    elif what == "onShown" and start is not None: shown = t
print(round((shown - start) * 1000) if start and shown else "?")' "$1"
}

scenario_measure() { # memory after typing a 6-word Phrase, focus-to-first-frame (cold and warm), outside our own app
    phrase="knhom tov sala rean nov phnom"
    "$ADB" shell am force-stop $PKG  # the Companion app must not share the Keyboard's process for this
    sleep 1
    select_keyboard
    "$ADB" logcat -c
    "$ADB" shell am start -W -f 0x10008000 -a android.intent.action.INSERT -t vnd.android.cursor.dir/contact >/dev/null
    xy=$(wait_for "First name" 30) || { log "FAIL measure: no Contacts form"; FAILED=1; return; }
    n=0
    until tap $xy && wait_for space 10 >/dev/null; do
        n=$((n + 1))
        [ $n -lt 4 ] || { log "FAIL measure: Keyboard did not open"; FAILED=1; return; }
    done
    log "  focus to first frame, cold (Keyboard process not running): $(show_ms com.google.android.contacts) ms"
    read_keys
    type_keys "$phrase"
    sleep 2
    shot measure-typed
    "$ADB" shell dumpsys meminfo $PKG >"$OUT/meminfo.txt"
    log "  memory after typing '$phrase': $(grep -E "TOTAL PSS|TOTAL RSS" "$OUT/meminfo.txt" | head -1 | tr -s ' ')"
    log "  $(grep -E "^ +Native Heap|^ +Java Heap|^ +Code" "$OUT/meminfo.txt" | tr -s ' ' | tr '\n' ';')"
    xy=$(ui bounds "abc, keep Latin") && tap $xy
    for i in 1 2 3; do
        "$ADB" shell input keyevent KEYCODE_BACK  # hide the Keyboard, the process stays
        sleep 1
        "$ADB" logcat -c
        set -- $(ui bounds "First name" 2>/dev/null || ui bounds "$phrase")
        tap "$@"
        wait_for space 20 >/dev/null
        log "  focus to first frame, warm ($i): $(show_ms com.google.android.contacts) ms"
    done
    "$ADB" shell input keyevent KEYCODE_BACK
    log "PASS measure: numbers recorded"
}

TALKBACK=com.google.android.marvin.talkback/com.google.android.marvin.talkback.TalkBackService
talkback() { # talkback on|off
    if [ "$1" = on ]; then
        "$ADB" shell pm grant com.google.android.marvin.talkback android.permission.POST_NOTIFICATIONS 2>/dev/null || true
        "$ADB" shell settings put secure enabled_accessibility_services $TALKBACK
        "$ADB" shell settings put secure accessibility_enabled 1
    else
        "$ADB" shell settings put secure enabled_accessibility_services '""'
        "$ADB" shell settings put secure accessibility_enabled 0
    fi
    sleep 3
}

# A touch from the emulator's own touchscreen (its console), so it goes through TalkBack's explore-by-touch like
# a finger would: `adb shell input` touches are injected past TalkBack and reach the Keyboard as plain touches.
# finger <x> <y> [shot]: touch, hold and drift a little (TalkBack moves its focus there and reads it), lift.
# With TalkBack's developer option "Display speech output" on, the screenshot shows what TalkBack said.
finger() {
    "$ADB" emu event mouse "$1" "$2" 0 1 >/dev/null
    sleep 0.3
    "$ADB" emu event mouse $(($1 + 3)) $(($2 + 2)) 0 1 >/dev/null
    sleep 0.4
    [ -z "${3:-}" ] || { sleep 0.5; shot "$3"; }
    "$ADB" emu event mouse $(($1 + 5)) $(($2 + 3)) 0 0 >/dev/null
}

# TalkBack on: explore by touch. A TalkBack user touches a key, hears it, lifts to type it; the Keyboard must type
# each key exactly once and let a Suggestion in the strip be picked the same way. uiautomator is an accessibility
# client too and Android pauses TalkBack while it reads the screen, so every position is read before TalkBack
# comes on and the field after it goes off; touch_exploration_enabled is checked around the touches.
scenario_talkback() {
    "$ADB" emu ping >/dev/null 2>&1 || { log "N/A talkback: needs the emulator console (adb emu), not a phone"; return; }
    open_app || { FAILED=1; return; }
    type_keys knhom  # dry run, TalkBack off: where does the ខ្ញុំ Suggestion sit?
    pick=$(wait_for "ខ្ញុំ" 20) || { log "FAIL talkback: no ខ្ញុំ in the strip (dry run)"; FAILED=1; return; }
    xy=$(ui bounds "abc, keep Latin") && tap $xy
    for _ in 1 2 3 4 5; do tap $(key_at delete); done
    [ -z "$(field_text)" ] || { log "FAIL talkback: could not empty the field before the run"; FAILED=1; return; }
    talkback on
    tb_on=$("$ADB" shell settings get secure touch_exploration_enabled | tr -d '\r')
    "$ADB" logcat -c
    # a human pace: touches much closer than this are taken by TalkBack's own gesture detection, not the Keyboard
    for c in k n h o m; do finger $(key_at $c) "talkback-says-$c"; sleep 1.5; done
    sleep 1.5
    shot talkback-typed
    finger $pick talkback-says-pick
    sleep 1.5
    shot talkback-picked
    tb_still=$("$ADB" shell settings get secure touch_exploration_enabled | tr -d '\r')
    "$ADB" logcat -d >"$OUT/talkback-logcat.txt" 2>/dev/null || true
    talkback off
    if [ "$tb_on" = 1 ] && [ "$tb_still" = 1 ]; then log "PASS talkback: touch exploration was on for every touch"
    else log "FAIL talkback: touch exploration was not on throughout (before '$tb_on', after '$tb_still')"; FAILED=1; fi
    text=$(field_text)
    if [ "$text" = "ខ្ញុំ" ]; then log "PASS talkback: knhom by explore-by-touch, then ខ្ញុំ from the strip: '$text'"
    else log "FAIL talkback: wanted exactly 'ខ្ញុំ', field holds '$text'"; FAILED=1; fi
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
for s in ${*:-tracer phrase learn password english keys talkback}; do
    log "-- $s"
    "scenario_$s"
done
"$ADB" logcat -d >"$OUT/logcat.txt" 2>/dev/null || true
log "artifacts: $OUT"
[ $FAILED = 0 ] && log "ALL PASSED" || log "FAILED"
exit $FAILED
