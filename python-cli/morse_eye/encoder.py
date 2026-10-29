"""Turn text into an LED on/off timeline using a user-editable code file.

A code file (JSON) looks like codes/morse.json:

    symbols      {"." : 1, "-": 3}  -> each symbol char and how many units the LED is ON
    symbol_gap   OFF units between symbols inside one character
    letter_gap   OFF units between characters
    word_gap     OFF units between words
    table        {"A": ".-", ...}   -> character -> sequence of symbols
    words        {"YES": "l", ...}  -> optional whole-word shortcuts (checked first)
    prefix/suffix  optional symbol sequences sent before/after the message
    ai_instructions  optional extra instruction given to the AI about what it may say
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Code:
    name: str
    symbols: dict[str, int]
    table: dict[str, str]
    words: dict[str, str] = field(default_factory=dict)
    symbol_gap: int = 1
    letter_gap: int = 3
    word_gap: int = 7
    prefix: str = ""
    suffix: str = ""
    case_sensitive: bool = False
    ai_instructions: str = ""

    @classmethod
    def load(cls, path: str | Path) -> "Code":
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        code = cls(
            name=data.get("name", Path(path).stem),
            symbols={k: int(v) for k, v in data["symbols"].items()},
            table=dict(data.get("table", {})),
            words=dict(data.get("words", {})),
            symbol_gap=int(data.get("symbol_gap", 1)),
            letter_gap=int(data.get("letter_gap", 3)),
            word_gap=int(data.get("word_gap", 7)),
            prefix=data.get("prefix", ""),
            suffix=data.get("suffix", ""),
            case_sensitive=bool(data.get("case_sensitive", False)),
            ai_instructions=data.get("ai_instructions", ""),
        )
        code.validate()
        return code

    def validate(self) -> None:
        for sym, units in self.symbols.items():
            if len(sym) != 1:
                raise ValueError(f"symbol {sym!r} must be a single character")
            if units <= 0:
                raise ValueError(f"symbol {sym!r} must have a positive ON duration")
        sources = {**self.table, **self.words, "<prefix>": self.prefix, "<suffix>": self.suffix}
        for key, seq in sources.items():
            bad = [c for c in seq if c not in self.symbols]
            if bad:
                raise ValueError(f"{key!r} uses undefined symbol(s) {bad}")

    def _norm(self, s: str) -> str:
        return s if self.case_sensitive else s.upper()

    @property
    def allowed_chars(self) -> str:
        """Characters the AI may use (for the prompt)."""
        return "".join(sorted(self.table))

    def sanitize(self, text: str) -> str:
        """Drop anything the code can't represent; collapse whitespace."""
        table = {self._norm(k) for k in self.table}
        words = {self._norm(k) for k in self.words}
        out = []
        for word in text.split():
            w = self._norm(word)
            bare = w.strip(".,!?;:'\"()")
            if bare in words:  # whole-word shortcut, ignoring surrounding punctuation
                out.append(bare)
                continue
            kept = "".join(c for c in w if c in table)
            if kept:
                out.append(kept)
        return " ".join(out)

    def encode(self, text: str) -> list[list[str]]:
        """Text -> list of words, each a list of symbol sequences (one per letter)."""
        table = {self._norm(k): v for k, v in self.table.items()}
        words = {self._norm(k): v for k, v in self.words.items()}
        result = []
        for word in self.sanitize(text).split():
            if word in words:
                result.append([words[word]])
            else:
                result.append([table[c] for c in word])
        return result

    def timeline(self, text: str) -> list[tuple[bool, int]]:
        """Text -> [(led_on, units), ...] including prefix/suffix framing."""
        words = self.encode(text)
        if self.prefix:
            words.insert(0, [self.prefix])
        if self.suffix:
            words.append([self.suffix])

        steps: list[tuple[bool, int]] = []
        for wi, letters in enumerate(words):
            if wi:
                steps.append((False, self.word_gap))
            for li, seq in enumerate(letters):
                if li:
                    steps.append((False, self.letter_gap))
                for si, sym in enumerate(seq):
                    if si:
                        steps.append((False, self.symbol_gap))
                    steps.append((True, self.symbols[sym]))
        return steps

    def pretty(self, text: str) -> str:
        """Human-readable rendering, e.g. '.- -... / -.-.'"""
        return " / ".join(" ".join(word) for word in self.encode(text))


def unit_seconds(wpm: float) -> float:
    """PARIS standard: one unit = 1.2 / WPM seconds."""
    return 1.2 / wpm
