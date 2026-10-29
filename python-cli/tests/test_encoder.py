from pathlib import Path

import pytest

from morse_eye.encoder import Code, unit_seconds

CODES = Path(__file__).resolve().parent.parent / "codes"


def morse():
    return Code.load(CODES / "morse.json")


def test_sos_pretty():
    assert morse().pretty("sos") == "... --- ..."


def test_sanitize_drops_unknown_chars():
    assert morse().sanitize("Hi *there*  ✨ ok") == "HI THERE OK"


def test_timeline_gaps_and_framing():
    c = morse()
    c.prefix = c.suffix = ""
    # E = . ; T = - ; "E T" -> on1, word gap, on3
    assert c.timeline("E T") == [(True, 1), (False, 7), (True, 3)]
    # "ET" -> on1, letter gap, on3
    assert c.timeline("ET") == [(True, 1), (False, 3), (True, 3)]
    assert c.timeline("A") == [(True, 1), (False, 1), (True, 3)]


def test_prefix_suffix_added():
    tl = morse().timeline("E")
    assert tl[0] == (True, 3)  # prefix "-.-.-" starts with a dash
    assert tl[-1] == (True, 1)  # suffix ".-.-." ends with a dot


def test_custom_code_words():
    c = Code.load(CODES / "simple_yes_no.json")
    assert c.sanitize("Yes, maybe!") == "YES MAYBE"
    assert c.timeline("YES") == [(True, 4)]
    assert c.timeline("12") == [(True, 1), (False, 4), (True, 1), (False, 1), (True, 1)]


def test_invalid_symbol_rejected(tmp_path):
    f = tmp_path / "bad.json"
    f.write_text('{"symbols": {".": 1}, "table": {"A": ".x"}}')
    with pytest.raises(ValueError):
        Code.load(f)


def test_paris_timing():
    assert unit_seconds(20) == pytest.approx(0.06)
