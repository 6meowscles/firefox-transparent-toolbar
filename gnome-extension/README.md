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

```sh
./install.sh
```

Then **log out and back in**. That last part is not skippable: GNOME enumerates
extensions only at startup, and `ReloadExtension` over D-Bus is a stub that returns
"deprecated and does not work", so on Wayland there is no shell restart to use
instead. On X11 the script tells you to press Alt+F2, `r`, Enter.

The script does the four manual commands and, more usefully, the checks that catch
the ways this silently does nothing:

- **`userchrome.wallpaper.on` still `true`.** The commonest one by far. The two
  mechanisms solve the same problem, and the stylesheet's copy is opaque and on
  top — so the extension loads, works perfectly, and is invisible. It reads
  exactly like an extension that failed.
- **`--content-backstop` not `transparent`.** Then the toolbar and sidebar go
  see-through while the page area stays an opaque slab.
- **Enabling an extension the shell has never heard of.** `gnome-extensions enable`
  goes through the running shell, so on a first install it just fails. The script
  falls back to writing `org.gnome.shell enabled-extensions` directly, which
  survives the logout.
- **`disable-user-extensions`** left on globally, which overrides everything else.
- **A shell version outside `metadata.json`**, which makes the shell refuse to load
  it with no visible error.

It finds your live Firefox profile through `installs.ini` rather than by directory
name, so it still checks the right one after a Refresh.

```sh
./install.sh --link       # symlink instead of copy: edits here go live
./install.sh --uninstall  # remove it and drop it from enabled-extensions
```

`--link` means editing this repo updates the installed extension, at the cost of
breaking it if the repo moves.

### Doing it by hand

```sh
UUID=firefox-wallpaper-underlay@localhost
mkdir -p ~/.local/share/gnome-shell/extensions/$UUID
cp extension.js metadata.json ~/.local/share/gnome-shell/extensions/$UUID/
# log out and back in, then:
gnome-extensions enable $UUID
```

Turn the stylesheet's own wallpaper mode **off** (`userchrome.wallpaper.on` →
`false`) when you use this. They solve the same problem, and the CSS copy would just
sit on top of the real thing at a slightly wrong offset.

### Why there is no one-click install

The only install path that skips the logout is `InstallRemoteExtension` over D-Bus,
and it only accepts UUIDs published on [extensions.gnome.org][ego] — the shell
downloads and loads those itself. Publishing there would make this a single click
and bring automatic updates, at the cost of a review queue and a UUID that is a
domain you control rather than `@localhost`. Nothing about the extension would have
to change apart from that UUID.

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
