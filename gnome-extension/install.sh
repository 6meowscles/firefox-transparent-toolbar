#!/usr/bin/env bash
#
# Install the Firefox Wallpaper Underlay GNOME Shell extension.
#
#     ./install.sh              copy the extension in and enable it
#     ./install.sh --link       symlink it instead, so edits here go live
#     ./install.sh --uninstall  remove it again
#
# The manual version of this is four commands and two things that are easy to
# get wrong: enabling an extension the running shell has never heard of, and
# leaving userchrome.wallpaper.on set to true so the stylesheet paints an
# opaque copy over the underlay and the extension looks broken. Both are
# checked here.
#
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ -t 1 ]; then
    red=$'\033[31m'; green=$'\033[32m'; yellow=$'\033[33m'
    bold=$'\033[1m'; dim=$'\033[2m'; off=$'\033[0m'
else
    red=; green=; yellow=; bold=; dim=; off=
fi
ok()   { printf '  %s✓%s %s\n' "$green"  "$off" "$*"; }
warn() { printf '  %s!%s %s\n' "$yellow" "$off" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$red"    "$off" "$*"; }
step() { printf '\n%s%s%s\n' "$bold" "$*" "$off"; }
die()  { bad "$*"; exit 1; }

link=0
uninstall=0
for arg in "$@"; do
    case $arg in
        --link)      link=1 ;;
        --uninstall) uninstall=1 ;;
        -h|--help)   sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           die "Unknown option: $arg (try --help)" ;;
    esac
done

command -v python3 >/dev/null || die "python3 is needed to read metadata.json."
uuid=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["uuid"])' \
       "$here/metadata.json")
dest="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$uuid"


# --- uninstall ------------------------------------------------------------
if [ "$uninstall" = 1 ]; then
    step "Removing $uuid"
    gnome-extensions disable "$uuid" 2>/dev/null || true
    # Drop it from the list too, or the shell re-enables it after the logout.
    python3 - "$uuid" <<'PY'
import subprocess, sys
uuid = sys.argv[1]
cur = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"],
                     capture_output=True, text=True).stdout.strip()
items = [i.strip().strip("'") for i in cur.strip("[]").split(",") if i.strip()]
if uuid in items:
    items.remove(uuid)
    subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions",
                    "[" + ", ".join(f"'{i}'" for i in items) + "]"], check=True)
    print("  removed from enabled-extensions")
PY
    rm -rf -- "$dest"
    ok "Deleted $dest"
    printf '\nLog out and back in to unload it from the running shell.\n'
    exit 0
fi


# --- compatibility --------------------------------------------------------
step "Checking this shell"

command -v gnome-extensions >/dev/null || die "gnome-extensions not found; is this GNOME?"

shell_version=$(gnome-shell --version 2>/dev/null | awk '{print $3}')
[ -n "$shell_version" ] || die "Could not read the GNOME Shell version."

if python3 - "$here/metadata.json" "$shell_version" <<'PY'
import json, sys
supported = json.load(open(sys.argv[1]))["shell-version"]
major = sys.argv[2].split(".")[0]
# metadata may list "50" or "50.4"; the shell matches on the major alone.
sys.exit(0 if any(s.split(".")[0] == major for s in supported) else 1)
PY
then
    ok "GNOME Shell $shell_version is supported"
else
    supported=$(python3 -c 'import json,sys; print(", ".join(json.load(open(sys.argv[1]))["shell-version"]))' "$here/metadata.json")
    warn "GNOME Shell $shell_version is not in metadata.json (shell-version: $supported)."
    warn "It will refuse to load. Add \"${shell_version%%.*}\" to that list if you want to try it."
fi

session=${XDG_SESSION_TYPE:-unknown}
ok "Session type: $session"


# --- install --------------------------------------------------------------
step "Installing to $dest"

existed=0
[ -e "$dest" ] && existed=1

mkdir -p -- "$dest"
rm -f -- "$dest/extension.js" "$dest/metadata.json"

if [ "$link" = 1 ]; then
    ln -s -- "$here/extension.js"  "$dest/extension.js"
    ln -s -- "$here/metadata.json" "$dest/metadata.json"
    ok "Symlinked (edits in $here go live at the next shell start)"
    warn "Moving or deleting this repo will break the installed extension."
else
    cp -- "$here/extension.js" "$here/metadata.json" "$dest/"
    ok "Copied extension.js and metadata.json"
fi


# --- enable ---------------------------------------------------------------
step "Enabling"

# `gnome-extensions enable` goes through the running shell, which only knows
# about extensions it enumerated at startup -- so on a first install it fails.
# Writing the key directly always works and survives the logout, which is what
# actually matters here.
if gnome-extensions enable "$uuid" 2>/dev/null; then
    ok "Enabled in the running shell"
else
    python3 - "$uuid" <<'PY'
import subprocess, sys
uuid = sys.argv[1]
cur = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"],
                     capture_output=True, text=True).stdout.strip()
items = [i.strip().strip("'") for i in cur.strip("[]").split(",") if i.strip()]
if uuid not in items:
    items.append(uuid)
    subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions",
                    "[" + ", ".join(f"'{i}'" for i in items) + "]"], check=True)
PY
    ok "Added to enabled-extensions; it will come up enabled after the logout"
fi

# Extensions are also gated by one global switch, which is easy to forget.
if [ "$(gsettings get org.gnome.shell disable-user-extensions)" = "true" ]; then
    warn "User extensions are globally disabled. Turning that off:"
    gsettings set org.gnome.shell disable-user-extensions false
    ok "org.gnome.shell disable-user-extensions -> false"
fi


# --- the stylesheet half --------------------------------------------------
step "Checking the Firefox side"

python3 <<'PY'
import configparser, os, re, sys

roots = [os.path.expanduser("~/.config/mozilla/firefox"),
         os.path.expanduser("~/.mozilla/firefox")]

def profile_dir():
    """The profile Firefox is actually using.

    installs.ini names the profile per installation and is what Firefox
    follows; profiles.ini's Default=1 is only the fallback. Guessing by
    directory name picks the wrong one after a Refresh, which leaves you
    editing files nothing reads.
    """
    for root in roots:
        if not os.path.isdir(root):
            continue
        installs = os.path.join(root, "installs.ini")
        if os.path.exists(installs):
            cp = configparser.ConfigParser()
            cp.read(installs)
            for sec in cp.sections():
                if cp.has_option(sec, "Default"):
                    return os.path.join(root, cp.get(sec, "Default"))
        profiles = os.path.join(root, "profiles.ini")
        if os.path.exists(profiles):
            cp = configparser.ConfigParser()
            cp.read(profiles)
            for sec in cp.sections():
                if cp.get(sec, "Default", fallback="") == "1" and cp.has_option(sec, "Path"):
                    return os.path.join(root, cp.get(sec, "Path"))
    return None

# Match the shell half: colour only when stdout is a terminal, so piping the
# output into a file or a log does not fill it with escape sequences.
GREEN, YELLOW, OFF = ("\033[32m", "\033[33m", "\033[0m") if sys.stdout.isatty() else ("", "", "")
def ok(m):   print(f"  {GREEN}✓{OFF} {m}")
def warn(m): print(f"  {YELLOW}!{OFF} {m}")

p = profile_dir()
if not p or not os.path.isdir(p):
    warn("Could not find a Firefox profile; skipping this check.")
else:
    ok(f"Profile: {p}")

    sheet = os.path.join(p, "chrome", "userChrome.css")
    if not os.path.exists(sheet):
        warn("No chrome/userChrome.css -- the extension changes what is BEHIND the")
        warn("window, not whether Firefox is transparent. Install the stylesheet too.")
    else:
        css = open(sheet, encoding="utf-8", errors="ignore").read()
        m = re.search(r"--content-backstop:\s*([^;]+);", css)
        if m and m.group(1).strip() != "transparent":
            warn(f"--content-backstop is {m.group(1).strip()}, not transparent -- the page")
            warn("area will stay an opaque slab while the toolbar goes see-through.")
        else:
            ok("userChrome.css is installed")

    # The one that actually bites: both wallpaper mechanisms switched on at
    # once. The stylesheet's copy is opaque and sits on top, so the extension
    # is invisible and looks like it never loaded.
    val = None
    for name in ("user.js", "prefs.js"):
        f = os.path.join(p, name)
        if not os.path.exists(f):
            continue
        for line in open(f, encoding="utf-8", errors="ignore"):
            hit = re.search(r'user_pref\(\s*"userchrome\.wallpaper\.on"\s*,\s*(\w+)', line)
            if hit:
                val = (hit.group(1), name)
    if val and val[0] == "true":
        warn(f"userchrome.wallpaper.on is TRUE (in {val[1]}).")
        warn("Set it to false, or the stylesheet paints an opaque wallpaper copy over")
        warn("the underlay and this extension will look like it did nothing.")
    elif val:
        ok("userchrome.wallpaper.on is false (correct for this extension)")
    else:
        warn("userchrome.wallpaper.on is not set; false is what this extension wants.")
PY


# --- what happens next ----------------------------------------------------
step "Next"

if gnome-extensions info "$uuid" >/dev/null 2>&1 && [ "$existed" = 1 ]; then
    printf '  The shell already has this extension loaded, but it reads extension.js\n'
    printf '  only at startup, so your changes are not live yet.\n'
fi

case $session in
    wayland)
        printf '  %sLog out and back in.%s GNOME enumerates extensions only at startup and\n' "$bold" "$off"
        printf '  ReloadExtension over D-Bus is a stub that returns "deprecated and does\n'
        printf '  not work", so on Wayland there is no way to skip this.\n' ;;
    x11)
        printf '  %sRestart the shell:%s Alt+F2, type %sr%s, Enter. (X11 only.)\n' "$bold" "$off" "$bold" "$off" ;;
    *)
        printf '  %sLog out and back in%s to load it.\n' "$bold" "$off" ;;
esac

printf '\n  Then check it took:\n'
printf '    %sgnome-extensions info %s%s\n' "$dim" "$uuid" "$off"
printf '  State: ACTIVE means it is running.\n\n'
