#!/usr/bin/env bash
#
# Run by pacman, as root, after gnome-shell is installed or upgraded. Warns if
# any installed copy of the extension does not declare the new major version.
#
# Root has no idea which user installed the extension, so look in every real
# user's home, plus the system-wide directory. A custom XDG_DATA_HOME is not
# visible from here and is missed.
#
# Always exits 0. A failing PostTransaction hook cannot undo the upgrade; it
# would only add an "error:" line that buries the warning that matters.
#
uuid=firefox-wallpaper-underlay@6meowscles.github.io

if [ -t 1 ]; then
    yellow=$'\033[1;33m'; off=$'\033[0m'
else
    yellow=; off=
fi

# pacman -Q prints "gnome-shell 1:51.0-1.1": drop the epoch, keep the major.
version=$(pacman -Q gnome-shell 2>/dev/null | awk '{print $2}')
version=${version#*:}
major=${version%%.*}
[ -n "$major" ] || exit 0

command -v python3 >/dev/null || {
    echo "  python3 not found; cannot read metadata.json, skipping."; exit 0; }

candidates=("/usr/share/gnome-shell/extensions/$uuid/metadata.json")
while IFS= read -r home; do
    candidates+=("$home/.local/share/gnome-shell/extensions/$uuid/metadata.json")
done < <(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {print $6}')

found=0
for meta in "${candidates[@]}"; do
    [ -f "$meta" ] || continue
    found=1
    # metadata may list "51" or "51.1"; the shell matches on the major alone.
    if python3 - "$meta" "$major" <<'PY'
import json, sys
try:
    supported = json.load(open(sys.argv[1]))["shell-version"]
except Exception:
    sys.exit(0)
sys.exit(0 if any(str(s).split(".")[0] == sys.argv[2] for s in supported) else 1)
PY
    then
        echo "  OK: $meta declares GNOME Shell $major."
    else
        printf '%s' "$yellow"
        echo "  WARNING: Firefox Wallpaper Underlay does not declare GNOME Shell $major."
        echo "  It is still running now, but will NOT load after your next login,"
        echo "  and the toolbar will show the window behind Firefox, not the wallpaper."
        printf '%s' "$off"
        echo "    $meta"
        echo "  Before logging out: pull the repo (or add \"$major\" to shell-version"
        echo "  in gnome-extension/metadata.json, after checking extension.js still"
        echo "  works on $major), then re-run gnome-extension/install.sh."
    fi
done

[ "$found" = 1 ] || echo "  Not installed for any user; nothing to check."
exit 0
