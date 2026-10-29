"""Morse Eye: hotkey -> screenshot -> AI -> blinking keyboard LED."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
from pathlib import Path

from . import ai
from .capture import take_screenshot
from .encoder import Code
from .leds import Player, make_led

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = ROOT / "config.json"
EXAMPLE_CONFIG = ROOT / "config.example.json"


def load_env(path: Path = ROOT / ".env") -> None:
    """Read API keys from a .env file (KEY=value lines). Real env vars win."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def load_config(path: Path) -> dict:
    if not path.exists():
        path = EXAMPLE_CONFIG
    cfg = json.loads(path.read_text(encoding="utf-8"))
    code_file = Path(cfg["code"]["file"])
    if not code_file.is_absolute():
        cfg["code"]["file"] = str((path.parent / code_file).resolve())
    return cfg


def notify(text: str) -> None:
    """Optional macOS banner so you know a capture happened."""
    if sys.platform == "darwin":
        subprocess.run(["osascript", "-e", f'display notification {json.dumps(text)} with title "Morse Eye"'],
                       check=False)


class MorseEye:
    def __init__(self, cfg: dict) -> None:
        self.cfg = cfg
        self.code = Code.load(cfg["code"]["file"])
        out = cfg.get("output", {})
        self.player = Player(make_led(out.get("device", "capslock"), out.get("backlight_level", 1.0)),
                             wpm=cfg["code"].get("wpm", 12), invert=out.get("invert", False))
        self.last_reply = ""
        self.busy = threading.Lock()

    def capture_and_answer(self, prompt: str) -> None:
        if not self.busy.acquire(blocking=False):
            print("Still working on the previous request, ignoring.")
            return
        try:
            print("📸 Capturing screen...")
            png = take_screenshot(self.cfg.get("screenshot", {}).get("display", 1),
                                  self.cfg.get("screenshot", {}).get("max_edge", 1568))
            if self.cfg.get("notify"):
                notify("Screenshot taken, asking AI...")
            p = ai.resolve(self.cfg["ai"])
            print(f"🤖 Asking {p['provider']} ({p['model']}): {prompt}")
            raw = ai.ask(png, prompt, self.code, self.cfg["ai"])
            reply = self.code.sanitize(raw) or "ERROR"
            self.last_reply = reply
            self.show_and_play(reply)
        except Exception as e:  # keep the hotkey listener alive no matter what
            print(f"❌ {e}")
            self.show_and_play("ERROR" if "ERROR" in self.code.words else "E")
        finally:
            self.busy.release()

    def show_and_play(self, reply: str) -> None:
        if self.cfg.get("print_reply", True):
            print(f"💬 {reply}\n   {self.code.pretty(reply)}")
        self.player.play(self.code, reply)
        print("✅ Done.")

    def replay(self) -> None:
        if self.last_reply:
            self.player.play(self.code, self.last_reply)

    def run_hotkeys(self) -> None:
        from pynput import keyboard

        def spawn(fn, *args):
            return lambda: threading.Thread(target=fn, args=args, daemon=True).start()

        bindings = {combo: spawn(self.capture_and_answer, prompt)
                    for combo, prompt in self.cfg["hotkeys"].items()}
        if self.cfg.get("abort_hotkey"):
            bindings[self.cfg["abort_hotkey"]] = self.player.abort
        if self.cfg.get("replay_hotkey"):
            bindings[self.cfg["replay_hotkey"]] = spawn(self.replay)

        print(f"Morse Eye ready. Code: {self.code.name}, "
              f"output: {self.cfg.get('output', {}).get('device', 'capslock')}")
        for combo, prompt in self.cfg["hotkeys"].items():
            print(f"  {combo:32} -> {prompt}")
        print(f"  {self.cfg.get('abort_hotkey', ''):32} -> stop blinking")
        print(f"  {self.cfg.get('replay_hotkey', ''):32} -> replay last answer")
        print("Ctrl+C to quit.")
        with keyboard.GlobalHotKeys(bindings) as listener:
            listener.join()


def main() -> None:
    p = argparse.ArgumentParser(prog="morse-eye", description=__doc__)
    p.add_argument("-c", "--config", type=Path, default=DEFAULT_CONFIG)
    p.add_argument("--once", metavar="PROMPT", nargs="?", const="",
                   help="capture & answer once, then exit (handy for the Shortcuts app)")
    p.add_argument("--test", metavar="TEXT", help="just blink TEXT, no screenshot or AI")
    p.add_argument("--device", help="override output device (capslock, backlight, console)")
    p.add_argument("--wpm", type=float, help="override speed in words per minute")
    args = p.parse_args()

    load_env()
    cfg = load_config(args.config)
    if args.device:
        cfg.setdefault("output", {})["device"] = args.device
    if args.wpm:
        cfg["code"]["wpm"] = args.wpm
    app = MorseEye(cfg)

    try:
        if args.test is not None:
            app.show_and_play(app.code.sanitize(args.test))
        elif args.once is not None:
            app.capture_and_answer(args.once or next(iter(cfg["hotkeys"].values())))
        else:
            app.run_hotkeys()
    except KeyboardInterrupt:
        app.player.abort()
        print("\nBye.")
