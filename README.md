# firefox-transparent-toolbar

A `userChrome.css` that makes the Firefox toolbar band — tab strip, address bar and
bookmarks bar — genuinely see-through to your desktop, not merely dark.

Written and tested against **Firefox 155 on Linux** (GNOME / Wayland).

![Firefox with a transparent toolbar floating over the desktop](assets/see-through-floating.jpg)

The window's chrome dissolves into whatever is behind it. Above, an unmaximized window —
the wallpaper runs straight through the toolbar and the page with no seam.

![The New Tab page continuing the desktop](assets/see-through-newtab.jpg)

Both shots are see-through mode over a bare desktop; wallpaper mode looks the same here
and only differs when another window sits behind Firefox. The vertical tab strip is a
Firefox setting, not part of this theme — it inherits the transparency like any other
toolbar.

## Why this isn't a theme

Themes can't do it. Firefox paints the window background from your theme's `frame`
colour, and treats that colour as opaque by definition — the comment is right there in
`browser-shared.css`:

```css
:root[lwtheme] & {
  background-color: var(--lwt-accent-color); /* Known opaque */
```

So a theme can set colours *within* an opaque window, but it can't remove the window's
backing. Themes that advertise transparency render as solid black for this reason. Only
a user stylesheet can clear `--lwt-accent-color`, which is what this file does.

## Install

1. **Find your profile folder.** Open `about:profiles` and copy the **Root Directory**
   of the profile marked *This is the profile in use*.

   Firefox 155 on Linux stores profiles under `~/.config/mozilla/firefox/<id>`.
   Older builds use `~/.mozilla/firefox/<id>`. Don't guess — check `about:profiles`,
   because writing to the wrong one looks exactly like the CSS silently not working.

2. **Drop the file in.**

   ```sh
   cd /path/to/your/profile
   mkdir -p chrome
   cp /path/to/userChrome.css chrome/
   ```

3. **Enable user stylesheets.** They've been off by default since Firefox 69. Either set
   `toolkit.legacyUserProfileCustomizations.stylesheets` to `true` in `about:config`, or
   put it in a `user.js` in the profile root so it survives a `prefs.js` rewrite:

   ```js
   user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
   ```

4. **Fully quit Firefox and start it again.** Not just closing the window — the process
   has to exit. Chrome CSS is read once, at startup.

## Tuning

Everything is driven by three variables at the top of the file:

| Variable | Default | What it does |
|---|---|---|
| `--bar-alpha` | `0.15` | Tint strength. `0` is fully see-through; raise it if text is hard to read over a busy wallpaper. |
| `--bar-tint` | `20 20 26` | The tint colour, as an `R G B` triplet. |
| `--content-backstop` | `#1b1b1f` | Painted behind pages that declare no background of their own, so they don't go see-through too. |

Restart after editing.


## Optional: a see-through page area too

By default the page area stays opaque, so the wallpaper stops at the bottom of the
bookmarks bar and the window looks half-finished. `userContent.css` carries it down the
rest of the window.

```sh
cp userContent.css /path/to/your/profile/chrome/
```

`embed-wallpaper.py` writes that file at the same time as `userChrome.css` — same image,
same screen size — so re-copy both after every run. Restart Firefox and the New Tab page
picks up exactly where the toolbar left off.

**It is a copy, not a hole.** The page area can't be made genuinely see-through on
Firefox 155. `about:newtab` renders in the privileged about content process and its
canvas is painted before any page style applies: clearing the background on `:root`,
`body`, `#root`, `.outer-wrapper` and `main`, with and without
`browser.tabs.allow_transparent_browser`, leaves the same opaque slab. A *red* background
set from the same file shows up fine, so the sheet is applying — the paint just isn't the
document's to remove.

So the page paints its own copy, anchored with `background-position: left bottom`. The
content viewport's bottom edge is the window's bottom edge, so on a maximized window that
lines the copy up with the real desktop exactly, with no offset to calibrate — verified
pixel-for-pixel against the source image. Same trade as wallpaper mode: correct while
maximized.

Pair it with wallpaper mode. In see-through mode the toolbar shows whatever is actually
behind the window while the page shows the copy, so the two only agree over a bare
desktop.

## Optional: wallpaper mode

True transparency is transparent to whatever is actually behind the window — which is
usually another window, not your desktop. If you want the wallpaper to show *regardless*
of what's behind Firefox, this mode paints your wallpaper as the window's own
background, positioned to line up with where the window sits on screen. Terminal
emulators call this pseudo-transparency.

Needs [Pillow](https://pypi.org/project/pillow/) (`pip install pillow`).

Run **one** of these — the second is the same command pointed at a file of your choice,
not a second step:

```sh
python3 embed-wallpaper.py               # reads your current GNOME wallpaper
python3 embed-wallpaper.py ~/pic.jpg     # ...or any image you like
```

Then copy the sheets into your profile, set `userchrome.wallpaper.on` to `true` in
`about:config`, and restart Firefox. The pref toggles live afterwards — `true` for the
wallpaper, `false` for genuine see-through.

**Copy both sheets, every time.** The script rewrites `userChrome.css` and
`userContent.css` together, and they position their copies by the same rule. Ship one
without the other and the toolbar and the page area disagree — the image reads as
offset across the whole window, which looks nothing like the "one file is stale" problem
it actually is.

```sh
cp userChrome.css userContent.css /path/to/your/profile/chrome/
```

Note the script writes the copy next to *itself*, not into your profile. Running it and
forgetting the `cp` leaves the profile on the previous image, which is the single
easiest way to lose an evening here.

The script scales and centre-crops the image to your screen the way GNOME's `zoom`
option does, so the copy matches the real desktop, then embeds it in the stylesheet as a
`data:` URI.

The size it targets is your screen in **logical** pixels, which is what chrome CSS is
laid out in — not the panel's physical mode. Those agree only at 100% scaling: a
2560x1600 panel at 133% is 1920x1200 to the stylesheet, and embedding 2560x1600 there
paints the wallpaper a third too large. The scale comes from `~/.config/monitors.xml`
and is divided out automatically; `--scale=1.3333` overrides the detected factor and
`--screen=1920x1200` overrides the result outright.

**Nothing to calibrate.** The copy is anchored to the window's bottom-right corner,
which on a maximized window *is* the screen's bottom-right corner — whatever the height
of your panel above it or the width of a sidebar beside it. `userContent.css` anchors the
same way, so the toolbar and the page agree across the seam. Verified pixel-for-pixel,
with and without vertical tabs.

If you keep your sidebar on the *right*, swap both sheets to `left bottom`: it's the
right edge that then stops being the window's.

**What you're trading.** It's a picture, not a window into the desktop, so it's only
aligned while Firefox is **maximized** — move or unmaximize it and the image stays put
while the window doesn't. It won't follow a wallpaper change either; re-run the script.
You can have "always shows the wallpaper" or "always correct as the window moves", not
both.

## Optional: the GNOME extension instead

Wallpaper mode trades alignment for always showing the wallpaper. `gnome-extension/`
removes the trade: it inserts the wallpaper into the compositor directly beneath the
Firefox window, clipped to the window, so the toolbar stays genuinely see-through,
ignores the windows in between, *and* stays aligned as the window moves.

```sh
cd gnome-extension && ./install.sh
```

Then log out and back in — GNOME only enumerates extensions at startup, and there is
no way around that on Wayland. The script also checks the two settings below, which
are the ways this silently does nothing. Full steps, before and after, in
[gnome-extension/README.md](gnome-extension/README.md).

Use one or the other — with the extension running, set `userchrome.wallpaper.on` back
to `false`, and make sure `--content-backstop` is `transparent` or the page area stays
an opaque slab while the toolbar goes see-through.

## Troubleshooting

**Nothing changed at all.** Confirm the pref is actually set and that you edited the
profile `about:profiles` says is in use. To prove the sheet is being loaded, add
`#nav-bar { background-color: #ff00ff !important; }` on the **first** line and restart —
a magenta address bar row means the file is live and the problem is elsewhere. Put it
first, not last: if anything further down the file is malformed, a probe at the end is
dropped along with it and you learn nothing.

**The bar is still a solid block, and the sheet *is* loading.** Your theme is probably
painting a `theme_frame` image. Firefox draws it on `<body>` whenever the image isn't in
the toolbox:

```css
:root:not([theme-image-in-toolbox]) body { background-image: var(--toolbox-background-image); }
```

Plenty of themes ship a flat single-colour band as that image, which covers the whole
toolbar and looks identical to an opaque background. This file already clears it. Note
the rule needs an `html|` prefix — a user stylesheet declares XUL as its default
namespace, so a bare `body` selector matches a XUL element and silently never applies.

**The bar goes dark instead of showing the desktop.** Your compositor isn't giving the
window an alpha channel. Nothing in CSS fixes that; raise `--bar-alpha` and treat it as
a tint instead.

**One toolbar row stays opaque grey.** On Linux, toolkit's `toolbar.css` paints every
`<toolbar>` with the GTK `-moz-headerbar` colour. Clearing `background` isn't enough
while the widget is still natively themed — it needs `appearance: none` too.

**Your edits do nothing, but the sheet was working before.** Chrome CSS is read once,
at process start, so a Firefox that was already running when you saved the file will
never see it — and closing the last window doesn't end the process. Compare the two
timestamps:

```sh
ps -o lstart= -p $(pgrep -f lib/firefox/firefox | head -1)
stat -c %y ~/.config/mozilla/firefox/*/chrome/userChrome.css
```

If the process is older than the file, that's the whole problem. `pkill firefox`, wait
for `pgrep firefox` to print nothing, then start it again.

**You used "Refresh Firefox" and everything stopped.** A reset creates a *new* profile
directory and parks the old one in `~/Desktop/Old Firefox Data`. Your `chrome/` folder
and your prefs stay behind with the old one, so the browser comes back looking untouched
while every file you edited is intact but unused. The new directory differs from the old
by eight random characters, so resolve it rather than eyeball it:

```sh
FF=$HOME/.config/mozilla/firefox
echo $FF/$(grep -m1 "^Default=" $FF/installs.ini | cut -d= -f2)
```

Keeping both prefs in `user.js` rather than `about:config` means the next reset costs
only the file copy — `prefs.js` is wiped, `user.js` is re-applied at every start.

**Wallpaper mode is on but you still get see-through.** Two things to check. The
stylesheet in your *profile* may still hold the 1×1 placeholder: an un-embedded file is
about 8 KB, an embedded one over a megabyte, so `ls -l` tells them apart at a glance.
And the pref has to exist as a real **Boolean** — `@media -moz-pref()` won't match a
string `"true"`. To prove the media query is matching, add this and restart; a green
address bar means wallpaper mode is live and the image is the thing to look at:

```css
@media -moz-pref("userchrome.wallpaper.on") { #nav-bar { background: lime !important; } }
```

**The toolbar and the page area show different parts of the image.** You copied one
sheet and not the other. They are generated together and position their copies by the
same rule; re-copy both and restart.

**Everything in the file stops applying at once.** Something structural is broken. An
unmatched `{` swallows the rest of the file, and a `/*` that lost its `*/` does the same
while leaving the braces looking balanced:

```sh
python3 -c "
t=open('userChrome.css',encoding='utf-8').read()
print('braces', t.count('{'), t.count('}'))
print('comments', t.count('/'+chr(42)), t.count(chr(42)+'/'))
"
```

Both pairs must match — 18 and 18, 20 and 20 for the shipped file. This is worth
checking any time you have hand-edited an embedded sheet: the `data:` URI is a single
line of roughly a megabyte, and some editors will happily reflow or truncate it.

**Check the whole install in one command.** Prints the profile Firefox actually uses,
whether both prefs are set, and whether the wallpaper is really embedded:

```sh
bash -c '
FF=$HOME/.config/mozilla/firefox
if [ ! -d "$FF" ]; then FF=$HOME/.mozilla/firefox; fi
P=$FF/$(grep -m1 "^Default=" "$FF/installs.ini" | cut -d= -f2)
S=$P/chrome/userChrome.css
echo "profile in use: $P"
if [ -f "$S" ]; then
  stat -c "  userChrome.css: %s bytes, saved %y" "$S"
  if grep -q "base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ" "$S"; then
    echo "  PLACEHOLDER - wallpaper not embedded"; else echo "  wallpaper embedded"; fi
else echo "  MISSING at $S"; fi
if [ -f "$P/chrome/userContent.css" ]; then echo "  userContent.css: present"
else echo "  userContent.css: absent (page area stays opaque)"; fi
grep -h "legacyUserProfileCustomizations" "$P/user.js" "$P/prefs.js" 2>/dev/null
grep -h "userchrome.wallpaper.on" "$P/user.js" "$P/prefs.js" 2>/dev/null
'
```

## A note on selector names

Firefox 155 renamed several theme variables. Older guides still reference
`--toolbar-bgcolor` and `--tab-selected-bgcolor`; the current names are
`--toolbar-background-color` and `--tab-background-color-selected`. If you're adapting an
older snippet and half of it seems to do nothing, that's usually why.

**The wallpaper doesn't paint, but the rest works.** The `data:` URL has to sit
literally in `background-image`. Routed through a custom property — `--wallpaper: url(...)`
then `background-image: var(--wallpaper)` — it parses without error and silently never
paints. Referencing the image by path doesn't work either: a chrome document won't load
a `file://` image, and a relative `url()` inside a custom property resolves against the
document's `chrome://` base URI rather than the stylesheet. Hence embedding.

## License

GPL-2.0-or-later — see [LICENSE](LICENSE). The GNOME extension is licensed the same
way, which is what extensions.gnome.org requires; see
[gnome-extension/SUBMISSION.md](gnome-extension/SUBMISSION.md).
