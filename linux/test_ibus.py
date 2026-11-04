#!/usr/bin/env python3
"""End-to-end check of the installed engine through a real ibus-daemon, as an app would use it.

Needs the .deb installed, python3-gi + gir1.2-ibus-1.0, and a running daemon:
  dbus-run-session -- sh -c 'ibus-daemon --panel=disable --daemonize && sleep 2 && python3 linux/test_ibus.py'
"""
import time

import gi

gi.require_version("IBus", "1.0")
from gi.repository import GLib, IBus  # noqa: E402

IBus.init()
bus = IBus.Bus()
assert bus.is_connected(), "no ibus-daemon"
ic = bus.create_input_context("typer-test")
committed = []
ic.connect("commit-text", lambda _ic, text: committed.append(text.get_text()))
modes = []  # top-bar indicator symbol, from the "InputMode" property
ic.connect("update-property", lambda _ic, p: modes.append(p.get_symbol().get_text()))
ic.set_capabilities(
    IBus.Capabilite.PREEDIT_TEXT | IBus.Capabilite.LOOKUP_TABLE | IBus.Capabilite.AUXILIARY_TEXT | IBus.Capabilite.FOCUS
    | IBus.Capabilite.PROPERTY  # else the daemon sends mode updates to the panel, not to us
)
ic.focus_in()
ic.set_engine("typer")


def pump(seconds=0.3):
    end = time.time() + seconds
    while time.time() < end:
        GLib.MainContext.default().iteration(False)
        time.sleep(0.01)


def key(keyval, release=False):
    state = IBus.ModifierType.RELEASE_MASK if release else 0
    handled = ic.process_key_event(keyval, 0, state)
    pump(0.05)
    return handled


def press(keyval):
    handled = key(keyval)
    key(keyval, release=True)
    return handled


def typed(text):
    for c in text:
        press(IBus.KEY_space if c == " " else ord(c))


def result(final_key):
    committed.clear()
    press(final_key)
    pump()
    return "".join(committed)


for _ in range(50):  # the daemon spawns the engine process on first use
    pump(0.1)
    engine = ic.get_engine()
    if engine and engine.get_name() == "typer":
        break
else:
    raise SystemExit("engine 'typer' never became active")

typed("knhom tov sala rean")
assert (got := result(IBus.KEY_Return)) == "ខ្ញុំទៅសាលារៀន", got

typed("hello")
assert (got := result(IBus.KEY_Tab)) == "hello", got  # Tab keeps the latin

typed("ban")
assert (got := result(ord("2"))) not in ("", "ban", "បាន"), got  # 2 picks the second candidate

typed("tov")
committed.clear()
assert not press(ord(".")), "punctuation should pass through to the app"
pump()
assert committed == ["ទៅ"], committed  # ...after inserting the top suggestion

key(IBus.KEY_Shift_L)  # Shift is for capitals, never a toggle
key(IBus.KEY_Shift_L, release=True)
assert "EN" not in modes, modes
key(IBus.KEY_Control_L)  # tap Ctrl alone: English mode
key(IBus.KEY_Control_L, release=True)
assert not press(ord("a")), "English mode should pass keys through"
assert modes[-1:] == ["EN"], modes
key(IBus.KEY_Control_L)
key(IBus.KEY_Control_L, release=True)
assert press(ord("a")), "back in Khmer mode"
assert modes[-1:] == ["ខ"], modes

print("ibus end-to-end: ok")
