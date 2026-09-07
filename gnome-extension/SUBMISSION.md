# Submitting to extensions.gnome.org

Publishing is the only way to make this a one-click install. `InstallRemoteExtension`
over D-Bus — the one path that loads an extension without a logout — accepts UUIDs
published on [extensions.gnome.org][ego] and nothing else. Everything below is done
except the parts that need your account.

[ego]: https://extensions.gnome.org/

## Already done

- **UUID** is `firefox-wallpaper-underlay@6meowscles.github.io`. It has to be a domain
  you control; `@localhost` is rejected. Changing it orphaned the old install
  directory, because GNOME requires the directory name to equal the UUID — `install.sh`
  now detects that and offers to remove it.
- **`url`** in `metadata.json` points at the repo. Reviewers use it to read the source
  in context.
- **Licensing.** GPL-2.0-or-later, matching GNOME Shell itself. `LICENSE` at the repo
  root, an SPDX header on `extension.js`, and the licence goes inside the bundle.
- **`shell-version`** lists `48`, `49`, `50` — released versions only. Listing an
  unreleased one is a rejection.
- **`disable()` fully reverses `enable()`.** This is the rule most submissions fail.
  Every signal is disconnected, every `BackgroundManager` destroyed, and the two Maps
  are nulled: the shell keeps the extension object alive across a disable, so a Map
  still holding `Meta.Window` keys would pin those windows for as long as the
  extension is merely switched off.
- **No work at import time.** The module only defines things; everything starts in
  `enable()`.
- **No `eval`, no network, no subprocesses, no monkeypatching of shell internals.**

## Build the bundle

```sh
cd ..                      # the repo root, so LICENSE resolves
gnome-extensions pack gnome-extension --force \
    --extra-source="$PWD/LICENSE" \
    --out-dir=/tmp
```

That writes `/tmp/firefox-wallpaper-underlay@6meowscles.github.io.shell-extension.zip`
containing exactly `metadata.json`, `extension.js` and `LICENSE`. `pack` only picks up
files it recognises, so `install.sh` and the READMEs are left out on their own —
which is what you want, since reviewers read the repo for context and the bundle for
code.

Check it before uploading:

```sh
unzip -l /tmp/firefox-wallpaper-underlay@6meowscles.github.io.shell-extension.zip
```

## Upload

1. Make an account at <https://extensions.gnome.org/accounts/register/>.
2. Upload the zip at <https://extensions.gnome.org/upload/>.
3. Wait. Review is by hand and volunteer-run — days to a few weeks is normal. You get
   an email either way, and rejections come with the reviewer's reasoning and a
   re-upload link.

Uploading again with the same UUID creates a new *version* of the same extension
rather than a second listing, so a rejection costs a re-upload, not a re-submission.
EGO assigns its own version number; the `version` field in `metadata.json` is not
what users see.

## Expect a question about the restacking

This extension inserts a `Meta.BackgroundActor` into `global.window_group` and moves
it on every restack. That is unusual enough that a reviewer may ask, and the answer
is in the header comment of `extension.js`. The short form:

> A transparent window shows what is directly below it in the stacking order, and
> Mutter has no "show the wallpaper specifically" mode. Rather than trying to make
> Firefox see further down, this lifts a copy of the monitor's background up to sit
> immediately below the Firefox window actor, clipped to the window's frame rect. The
> actor is anchored to the monitor and only the clip follows the window, so it stays
> pixel-aligned with the real desktop. Nothing outside that clip is touched, and the
> actor is destroyed with the window.

Worth saying in the submission notes up front rather than waiting to be asked.

## After it is accepted

- **Bumping.** Edit the source, re-pack, upload the same UUID again.
- **New shell releases.** Add the version to `shell-version` and re-upload; there is
  no way to widen the range without a new upload.
- **`install.sh` stays useful** for development — `--link` symlinks the repo in, which
  publishing does not give you.

## Still worth knowing

The extension is only half of this. It changes what is *behind* the Firefox window,
not whether Firefox is transparent — that is `userChrome.css`'s job, and users
arriving from extensions.gnome.org will not have it. The description and `url` both
say so, and it is the first thing to point at when someone reports "installed it,
nothing happened".
