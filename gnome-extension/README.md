# Firefox Wallpaper Underlay

A GNOME Shell extension that makes the see-through toolbar show your **wallpaper**
instead of whatever window happens to be behind Firefox — without giving up real
transparency, and without the alignment problem that `userChrome.css`'s
[wallpaper mode](../README.md#optional-wallpaper-mode) has.

Tested against **GNOME Shell 50.4** on Wayland.

## Why an extension is the only way

A transparent pixel shows what is *directly below it in the stacking order*. Below
Firefox is the next window down, not the desktop, and neither Wayland nor Mutter has
a "see through to the wallpaper specifically" mode. No stylesheet can reach past that
layer, because the stylesheet isn't the thing doing the compositing.

The `userChrome.css` wallpaper mode works around it by painting a *copy* of the
wallpaper as the window's own background. That ignores the windows in between, but
the copy is a picture at a fixed offset, so it only lines up while the window is
maximized.

This extension inverts the trick. Instead of asking Firefox to see further down, it
lifts the wallpaper up: a `Meta.BackgroundActor` for the monitor is inserted into
`global.window_group` immediately below the Firefox window actor, and clipped to the
window's frame rect.

```
window_group (bottom -> top)
  MetaBackgroundGroup          <- the real desktop
  MetaWindowActor (editor)     <- masked, but only inside the clip
  MetaBackgroundActor          <- this extension, clip = Firefox's frame rect
  MetaWindowActor (firefox)    <- its transparent pixels now land on wallpaper
```

Because the actor is anchored to the monitor and only the *clip* follows the window,
the image behind Firefox is the part of the wallpaper that genuinely belongs at that
spot on screen. Move or unmaximize the window and it stays aligned — no
`--wallpaper-offset-y` to calibrate, and no re-running a script when you change
wallpaper.

## Install

### Before you run it

1. **Install the stylesheet first, and confirm it works.** This extension changes what
   is *behind* the Firefox window; it does not make Firefox transparent — that is
   `userChrome.css`'s job. Follow [the main README](../README.md#install) and check
   the toolbar is already see-through. Adding the extension to an opaque Firefox looks
   exactly like an extension that failed to load.

2. **Turn the stylesheet's wallpaper mode off.** In your profile's `user.js`:

   ```js
   user_pref("userchrome.wallpaper.on", false);
   ```

   In `user.js`, not `about:config` — `user.js` is re-applied at every start, so it
   would put the old value straight back. The two mechanisms solve the same problem,
   and the stylesheet's copy is opaque and sits on top, so leaving this `true` hides
   the extension completely while it runs perfectly.

3. **Check `--content-backstop` is `transparent`** near the top of `userChrome.css`.
   A colour there makes the page area an opaque slab while the toolbar and sidebar go
   see-through.

4. **Check your shell.** `gnome-shell --version` should be 48, 49 or 50.

5. **Get the files.**

   ```sh
   git clone https://github.com/6meowscles/firefox-transparent-toolbar
   cd firefox-transparent-toolbar/gnome-extension
   ```

Steps 1–4 are all checked by the script, so you can equally just run it and read what
it tells you.

### Run it

```sh
./install.sh
```

If it is not executable, `chmod +x install.sh` or run `bash install.sh`.

It copies the extension in, enables it, cleans up an install left under an older
UUID, and reports on the Firefox side. Nothing it does needs root.

### After you run it

1. **Log out and back in.** Not optional on Wayland: GNOME enumerates extensions only
   at startup, and `ReloadExtension` over D-Bus is a stub that returns "deprecated and
   does not work". On X11 you can press Alt+F2, type `r`, Enter instead.

2. **Check the extension loaded.**

   ```sh
   gnome-extensions info firefox-wallpaper-underlay@6meowscles.github.io
   ```

   `State: ACTIVE` means it is running. `INITIALIZED` or `INACTIVE` means it is
   installed but not enabled; `ERROR` means it threw, and

   ```sh
   journalctl --user -b -o cat | grep wallpaper-underlay
   ```

   will say why.

3. **Fully quit Firefox and start it again** — all windows, process gone. Chrome CSS
   is only read at startup, so if you changed `user.js` or `userChrome.css` in the
   steps above, this is when it takes effect.

4. **Confirm it is the real underlay and not a painted copy.** Unmaximize the window
   and drag it around. The wallpaper behind the toolbar should *track the window* and
   stay lined up with the desktop. If the image stays put while the window moves, you
   are looking at the stylesheet's copy and wallpaper mode is still on.

### What the script checks

The install commands were never really the hard part. These are, because each one
fails silently:

- **`userchrome.wallpaper.on` still `true`** — the commonest by far. The extension
  loads, works, and is invisible under the stylesheet's opaque copy.
- **`--content-backstop` not `transparent`** — page area stays a slab.
- **Enabling an extension the shell has never heard of.** `gnome-extensions enable`
  goes through the running shell, so on a first install it just fails. The script
  falls back to writing `org.gnome.shell enabled-extensions` directly, which survives
  the logout.
- **`disable-user-extensions`** left on globally, which overrides everything else.
- **A shell version outside `metadata.json`**, which makes the shell refuse to load it
  with no visible error.
- **An install under an older UUID.** GNOME requires the directory name to equal
  `metadata.json`'s `uuid`, so a leftover directory is a second, permanently broken
  extension rather than dead weight.

It resolves your Firefox profile through `installs.ini` rather than by directory name,
so it still checks the right one after a Refresh.

### Options

```sh
./install.sh --link       # symlink instead of copy: edits here go live
./install.sh --uninstall  # remove it and drop it from enabled-extensions
```

`--link` means editing this repo updates the installed extension, at the cost of
breaking it if the repo moves.

### Doing it by hand

```sh
UUID=firefox-wallpaper-underlay@6meowscles.github.io
mkdir -p ~/.local/share/gnome-shell/extensions/$UUID
cp extension.js metadata.json ~/.local/share/gnome-shell/extensions/$UUID/
# log out and back in, then:
gnome-extensions enable $UUID
```

The directory name must match `uuid` in `metadata.json` exactly, or the shell skips it.

### Why there is no one-click install

The only install path that skips the logout is `InstallRemoteExtension` over D-Bus,
and it only accepts UUIDs published on [extensions.gnome.org][ego] — the shell
downloads and loads those itself. Publishing would make this a single click and bring
automatic updates, at the cost of a review queue. See [SUBMISSION.md](SUBMISSION.md);
the prep is done.

[ego]: https://extensions.gnome.org/

## Tuning

`WM_CLASS_RE` at the top of `extension.js` decides which windows get an underlay. It
matches `firefox`, `librewolf`, `waterfox` and `floorp` today; add your own if you
run something else.

## Known limits

- **Square corners.** The clip is the window's frame rect, so the rounded top corners
  get wallpaper in the notch rather than the window behind. A few pixels.
- **Workspace-switch animation.** Window actors get reparented out of
  `window_group` while a switch animates; the underlay stays put and is skipped
  rather than restacked across parents, so it can flicker for the length of the
  animation.
- **One actor per window.** Each Firefox window gets its own `BackgroundManager`.
  Fine for a handful of windows; it isn't built for dozens.
- **Only helps where Firefox is actually transparent.** It changes what is behind the
  window, not whether Firefox has an alpha channel — that's still `userChrome.css`'s
  job.
- **The hovered sidebar is still a copy, so you still need `embed-wallpaper.py`.** When
  the launcher expands it floats *over* the page, and CSS cannot reach the compositor's
  underlay to fill it — so the stylesheet paints a wallpaper copy there in both modes.
  That copy is anchored to the window while the underlay is anchored to the monitor, so
  it is gated on `html|html[sizemode="maximized"]`: correct maximized, and a plain scrim
  otherwise rather than a visibly misaligned seam. Skip the embed step and it falls back
  to that scrim permanently.
- **The sidebar can stay expanded after the window idles.** Firefox's `expand-on-hover`
  launcher keeps its `:hover` state when the pointer stops being over it without a leave
  event reaching Gecko. Nothing here can un-latch it; moving the pointer onto the sidebar
  or Alt-Tabbing clears it. See the
  [main README's troubleshooting](../README.md#troubleshooting).
