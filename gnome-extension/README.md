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

GNOME only enumerates extensions at startup, and `ReloadExtension` over D-Bus is now
a stub that returns "deprecated and does not work" — so on Wayland this needs a
logout, not a shell restart.

```sh
UUID=firefox-wallpaper-underlay@localhost
mkdir -p ~/.local/share/gnome-shell/extensions/$UUID
cp extension.js metadata.json ~/.local/share/gnome-shell/extensions/$UUID/
```

Then log out and back in, and:

```sh
gnome-extensions enable firefox-wallpaper-underlay@localhost
```

Symlinking the two files instead of copying works too, and means editing this repo
updates the installed extension — at the cost of breaking it if the repo moves.

Turn the stylesheet's own wallpaper mode **off** (`userchrome.wallpaper.on` →
`false`) when you use this. They solve the same problem, and the CSS copy would just
sit on top of the real thing at a slightly wrong offset.

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
