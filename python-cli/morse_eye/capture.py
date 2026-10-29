"""Screenshots using macOS' built-in `screencapture` and `sips` tools."""

from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

MEDIA_TYPE = "image/jpeg"


def take_screenshot(display: int = 1, max_edge: int = 1568, quality: int = 80) -> bytes:
    """Capture a display silently and return JPEG bytes, downscaled so the
    longest edge is at most `max_edge` px. JPEG keeps requests small: some
    providers (e.g. Groq) cap the size of images sent inline.

    display: 1 = main display, 2 = second display, ...
    """
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "shot.jpg"
        # -x: no shutter sound, -D: which display, -t: format
        subprocess.run(["screencapture", "-x", "-D", str(display), "-t", "jpg", str(path)],
                       check=True)
        if not path.exists() or path.stat().st_size == 0:
            raise RuntimeError(
                "Screenshot came back empty. Grant Screen Recording permission to your "
                "terminal (System Settings > Privacy & Security > Screen Recording)."
            )
        sips = ["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(quality)]
        if max_edge:
            sips += ["-Z", str(max_edge)]
        subprocess.run(sips + [str(path)], check=True, stdout=subprocess.DEVNULL)
        return path.read_bytes()
