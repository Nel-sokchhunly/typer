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
tap() { "$ADB" shell input tap "$1" "$2"; }

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

log "Typer Android e2e $(date)  device: $("$ADB" shell getprop ro.product.model | tr -d '\r') API $("$ADB" shell getprop ro.build.version.sdk | tr -d '\r')"
for s in ${*:-tracer}; do
    log "-- $s"
    "scenario_$s"
done
"$ADB" logcat -d >"$OUT/logcat.txt" 2>/dev/null || true
log "artifacts: $OUT"
[ $FAILED = 0 ] && log "ALL PASSED" || log "FAILED"
exit $FAILED
