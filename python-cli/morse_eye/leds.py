"""LED outputs for macOS.

capslock   - Caps Lock LED via IOKit (IOHIDSetModifierLockState). Note this really
             toggles Caps Lock, so typing during playback comes out in capitals.
             The original state is restored when the message finishes.
backlight  - Built-in MacBook keyboard backlight via the private CoreBrightness
             framework (needs `pyobjc`). Works on most Apple Silicon / recent
             Intel MacBooks; external keyboards are not supported.
console    - Prints a blinking dot in the terminal. Useful for testing.
"""

from __future__ import annotations

import ctypes
import ctypes.util
import sys
import threading
import time

from .encoder import Code, unit_seconds


class Led:
    def setup(self) -> None: ...
    def set(self, on: bool) -> None: raise NotImplementedError
    def restore(self) -> None: ...


class ConsoleLed(Led):
    def set(self, on: bool) -> None:
        sys.stdout.write("\r● " if on else "\r○ ")
        sys.stdout.flush()

    def restore(self) -> None:
        sys.stdout.write("\r  \r")
        sys.stdout.flush()


class CapsLockLed(Led):
    """IOKit: open the IOHIDSystem service and set the Caps Lock modifier state."""

    kIOHIDParamConnectType = 1
    kIOHIDCapsLockState = 1

    def __init__(self) -> None:
        iokit = ctypes.cdll.LoadLibrary(ctypes.util.find_library("IOKit"))
        libc = ctypes.cdll.LoadLibrary(ctypes.util.find_library("c"))

        iokit.IOServiceMatching.restype = ctypes.c_void_p
        iokit.IOServiceMatching.argtypes = [ctypes.c_char_p]
        iokit.IOServiceGetMatchingService.restype = ctypes.c_uint32
        iokit.IOServiceGetMatchingService.argtypes = [ctypes.c_uint32, ctypes.c_void_p]
        iokit.IOServiceOpen.restype = ctypes.c_int
        iokit.IOServiceOpen.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32,
                                        ctypes.POINTER(ctypes.c_uint32)]
        iokit.IOHIDSetModifierLockState.restype = ctypes.c_int
        iokit.IOHIDSetModifierLockState.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_bool]
        iokit.IOHIDGetModifierLockState.restype = ctypes.c_int
        iokit.IOHIDGetModifierLockState.argtypes = [ctypes.c_uint32, ctypes.c_int,
                                                    ctypes.POINTER(ctypes.c_bool)]
        self.iokit = iokit

        service = iokit.IOServiceGetMatchingService(0, iokit.IOServiceMatching(b"IOHIDSystem"))
        if not service:
            raise RuntimeError("IOHIDSystem service not found")
        task = ctypes.c_uint32.in_dll(libc, "mach_task_self_")
        self.conn = ctypes.c_uint32()
        rc = iokit.IOServiceOpen(service, task, self.kIOHIDParamConnectType, ctypes.byref(self.conn))
        iokit.IOObjectRelease(service)
        if rc != 0:
            raise RuntimeError(f"IOServiceOpen failed ({rc:#x})")
        self.original = False

    def _get(self) -> bool:
        state = ctypes.c_bool()
        self.iokit.IOHIDGetModifierLockState(self.conn, self.kIOHIDCapsLockState, ctypes.byref(state))
        return state.value

    def setup(self) -> None:
        self.original = self._get()

    def set(self, on: bool) -> None:
        self.iokit.IOHIDSetModifierLockState(self.conn, self.kIOHIDCapsLockState, on)

    def restore(self) -> None:
        self.set(self.original)


class BacklightLed(Led):
    """Keyboard backlight through CoreBrightness' KeyboardBrightnessClient (private API)."""

    def __init__(self, on_level: float = 1.0) -> None:
        import objc  # pyobjc

        bundle = {}
        objc.loadBundle("CoreBrightness", bundle,
                        bundle_path="/System/Library/PrivateFrameworks/CoreBrightness.framework")
        self.client = objc.lookUpClass("KeyboardBrightnessClient").alloc().init()
        ids = self.client.copyKeyboardBacklightIDs()
        if not ids:
            raise RuntimeError("no built-in keyboard backlight found")
        self.kb = int(ids[0])
        self.on_level = on_level
        self.original = 0.0
        self.original_auto = None

    def setup(self) -> None:
        self.original = float(self.client.brightnessForKeyboard_(self.kb))
        try:
            self.original_auto = bool(self.client.isAutoBrightnessEnabledForKeyboard_(self.kb))
            self.client.enableAutoBrightness_forKeyboard_(False, self.kb)
        except AttributeError:
            self.original_auto = None

    def set(self, on: bool) -> None:
        level = self.on_level if on else 0.0
        if hasattr(self.client, "setBrightness_fadeSpeed_commit_forKeyboard_"):
            # fadeSpeed 0 = switch instantly instead of the normal slow fade
            self.client.setBrightness_fadeSpeed_commit_forKeyboard_(level, 0, True, self.kb)
        else:
            self.client.setBrightness_forKeyboard_(level, self.kb)

    def restore(self) -> None:
        self.client.setBrightness_forKeyboard_(self.original, self.kb)
        if self.original_auto is not None:
            self.client.enableAutoBrightness_forKeyboard_(self.original_auto, self.kb)


def make_led(name: str, backlight_level: float = 1.0) -> Led:
    if name == "console":
        return ConsoleLed()
    if sys.platform != "darwin":
        raise RuntimeError(f"'{name}' output only works on macOS; use 'console' to test elsewhere")
    if name == "capslock":
        return CapsLockLed()
    if name == "backlight":
        return BacklightLed(backlight_level)
    raise ValueError(f"unknown output device {name!r} (capslock, backlight, console)")


class Player:
    """Plays timelines on an LED in a background thread; can be aborted."""

    def __init__(self, led: Led, wpm: float, invert: bool = False) -> None:
        self.led = led
        self.unit = unit_seconds(wpm)
        self.invert = invert
        self._abort = threading.Event()
        self._lock = threading.Lock()

    def abort(self) -> None:
        self._abort.set()

    def play(self, code: Code, text: str) -> None:
        with self._lock:  # one message at a time
            self._abort.clear()
            self.led.setup()
            try:
                for on, units in code.timeline(text):
                    self.led.set(on != self.invert)
                    if self._abort.wait(units * self.unit):
                        break
            finally:
                self.led.set(self.invert)
                time.sleep(self.unit)
                self.led.restore()
