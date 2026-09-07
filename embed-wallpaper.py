#!/usr/bin/env python3
"""Embed your desktop wallpaper into userChrome.css as a data: URI.

    python3 embed-wallpaper.py [/path/to/wallpaper] [--screen 1920x1080]
                               [--scale 1.3333]

With no path it reads the current GNOME wallpaper from gsettings. Then set
userchrome.wallpaper.on to true in about:config and restart Firefox.

Screen size is measured in LOGICAL (CSS) pixels, which is what Firefox's
chrome stylesheet is laid out in -- not the panel's physical mode. The two
agree only at 100% scaling; on a 2560x1600 panel at 133% the stylesheet sees
1920x1200, and embedding the physical size paints the wallpaper a third too
large. GNOME records both numbers in ~/.config/monitors.xml, so the scale is
read from there and divided out. --scale overrides the detected factor,
--screen overrides the result outright.

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
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote

from PIL import Image

SHEET = Path(__file__).with_name("userChrome.css")
CONTENT_SHEET = Path(__file__).with_name("userContent.css")


def gnome_wallpaper() -> str:
    for key in ("picture-uri-dark", "picture-uri"):
        out = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.background", key],
            capture_output=True, text=True).stdout.strip().strip("'")
        if out:
            return unquote(out.removeprefix("file://"))
    sys.exit("Could not read the GNOME wallpaper; pass a path instead.")


def drm_mode() -> tuple[int, int] | None:
    """The panel's physical mode, straight from the kernel."""
    for modes in sorted(Path("/sys/class/drm").glob("*/modes")):
        try:
            first = modes.read_text().split("\n", 1)[0]
        except OSError:
            continue
        if re.fullmatch(r"\d+x\d+", first):
            w, h = first.split("x")
            return int(w), int(h)
    return None


def monitor_scale(physical: tuple[int, int] | None) -> float | None:
    """The scale factor GNOME is applying, from ~/.config/monitors.xml.

    The file keeps one <configuration> per set of connected monitors, so when
    the physical mode is known it disambiguates: pick the entry whose mode
    matches the panel we measured, and fall back to the primary otherwise.
    """
    try:
        root = ET.parse(Path.home() / ".config" / "monitors.xml").getroot()
    except (OSError, ET.ParseError):
        return None

    primary_scale = None
    for logical in root.iter("logicalmonitor"):
        mode = logical.find("monitor/mode")
        if mode is None:
            continue
        try:
            scale = float(logical.findtext("scale", "1"))
            size = (int(mode.findtext("width")), int(mode.findtext("height")))
        except (TypeError, ValueError):
            continue
        if physical is not None and size == physical:
            return scale
        if primary_scale is None and (logical.findtext("primary") or "").strip() == "yes":
            primary_scale = scale
    return primary_scale


def screen_size(scale_override: float | None = None) -> tuple[int, int]:
    """The screen in logical pixels -- the units the stylesheet is read in."""
    physical = drm_mode()
    if physical is None:
        sys.exit("Could not detect screen size; pass --screen WIDTHxHEIGHT.")

    scale = scale_override if scale_override else monitor_scale(physical) or 1.0
    if scale <= 0:
        sys.exit(f"Nonsensical display scale {scale}; pass --screen WIDTHxHEIGHT.")

    logical = (round(physical[0] / scale), round(physical[1] / scale))
    if logical != physical:
        print(f"Display {physical[0]}x{physical[1]} at {scale:g}x scale "
              f"-> {logical[0]}x{logical[1]} logical pixels.")
    return logical


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

    scale = None
    for f in flags:
        if f.startswith("--scale="):
            scale = float(f.split("=", 1)[1])

    size = screen_size(scale)
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
    # Two of them now: the window's own layer, and the sidebar's copy.
    css, n = re.subn(r'url\("data:image/[a-z]+;base64,[A-Za-z0-9+/=]*"\)',
                     f'url("data:image/jpeg;base64,{b64}")', css)
    if not n:
        sys.exit("No wallpaper url() found in userChrome.css")
    css = re.sub(r"--wallpaper-screen-w: \d+px;", f"--wallpaper-screen-w: {size[0]}px;", css)
    css = re.sub(r"--wallpaper-screen-h: \d+px;", f"--wallpaper-screen-h: {size[1]}px;", css)
    # The sidebar rule can't use those variables, so its size is literal.
    css = re.sub(r"/ \d+px \d+px no-repeat scroll",
                 f"/ {size[0]}px {size[1]}px no-repeat scroll", css)
    SHEET.write_text(css)

    print(f"Embedded {src} at {size[0]}x{size[1]} "
          f"({len(b64) / 1024:.0f} KB base64, {n} place{'s' if n > 1 else ''}).")
    if update_content_sheet(b64, size):
        print(f"Updated {CONTENT_SHEET.name} to match "
              "(copy it beside userChrome.css for a see-through page area).")
    print("Now set userchrome.wallpaper.on to true in about:config, and restart Firefox.")


def update_content_sheet(b64: str, size: tuple[int, int]) -> bool:
    """Mirror the image and the screen size into userContent.css."""
    if not CONTENT_SHEET.exists():
        return False

    css = CONTENT_SHEET.read_text()
    css, n = re.subn(r'url\("data:image/[a-z]+;base64,[A-Za-z0-9+/=]*"\)',
                     f'url("data:image/jpeg;base64,{b64}")', css, count=1)
    if not n:
        return False
    css = re.sub(r"background-size: \d+px \d+px",
                 f"background-size: {size[0]}px {size[1]}px", css)
    CONTENT_SHEET.write_text(css)
    return True


if __name__ == "__main__":
    main()
