#!/usr/bin/env python3
"""Embed your desktop wallpaper into userChrome.css as a data: URI.

    python3 embed-wallpaper.py [/path/to/wallpaper] [--screen 1920x1080]

With no path it reads the current GNOME wallpaper from gsettings. Screen size
is detected from /sys/class/drm when not given. Then set
userchrome.wallpaper.on to true in about:config and restart Firefox.

The image is embedded rather than referenced because a chrome document won't
load a file:// image, and a relative url() inside a custom property resolves
against the document's chrome:// base URI rather than this stylesheet -- so
neither path form ever loads. It is also written into background-image
literally: routed through var(), it parses fine but never paints.

The wallpaper is scaled and centre-cropped to the screen the way GNOME's
'zoom' option does, so the copy lines up with the real desktop behind it.
"""
import base64
import io
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

from PIL import Image

SHEET = Path(__file__).with_name("userChrome.css")


def gnome_wallpaper() -> str:
    for key in ("picture-uri-dark", "picture-uri"):
        out = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.background", key],
            capture_output=True, text=True).stdout.strip().strip("'")
        if out:
            return unquote(out.removeprefix("file://"))
    sys.exit("Could not read the GNOME wallpaper; pass a path instead.")


def screen_size() -> tuple[int, int]:
    for modes in sorted(Path("/sys/class/drm").glob("*/modes")):
        try:
            first = modes.read_text().split("\n", 1)[0]
        except OSError:
            continue
        if re.fullmatch(r"\d+x\d+", first):
            w, h = first.split("x")
            return int(w), int(h)
    sys.exit("Could not detect screen size; pass --screen WIDTHxHEIGHT.")


def cover(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Scale and centre-crop, matching GNOME's 'zoom' picture-option."""
    sw, sh = size
    scale = max(sw / img.width, sh / img.height)
    scaled = img.resize((round(img.width * scale), round(img.height * scale)),
                        Image.LANCZOS)
    left = (scaled.width - sw) // 2
    top = (scaled.height - sh) // 2
    return scaled.crop((left, top, left + sw, top + sh))


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]

    size = screen_size()
    for f in flags:
        if f.startswith("--screen="):
            w, h = f.split("=", 1)[1].split("x")
            size = (int(w), int(h))

    src = args[0] if args else gnome_wallpaper()
    img = cover(Image.open(src).convert("RGB"), size)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=82, optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode()

    css = SHEET.read_text()
    css, n = re.subn(r'background-image: url\("data:image/[a-z]+;base64,[A-Za-z0-9+/=]*"\)',
                     f'background-image: url("data:image/jpeg;base64,{b64}")',
                     css, count=1)
    if not n:
        sys.exit("No wallpaper background-image declaration found in userChrome.css")
    css = re.sub(r"--wallpaper-screen-w: \d+px;", f"--wallpaper-screen-w: {size[0]}px;", css)
    css = re.sub(r"--wallpaper-screen-h: \d+px;", f"--wallpaper-screen-h: {size[1]}px;", css)
    SHEET.write_text(css)

    print(f"Embedded {src} at {size[0]}x{size[1]} ({len(b64) / 1024:.0f} KB base64).")
    print("Now set userchrome.wallpaper.on to true in about:config, and restart Firefox.")


if __name__ == "__main__":
    main()
