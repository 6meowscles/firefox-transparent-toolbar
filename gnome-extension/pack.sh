#!/usr/bin/env bash
#
# Build the extensions.gnome.org bundle.
#
#     ./pack.sh [OUT_DIR]      # OUT_DIR defaults to /tmp
#
# `gnome-extensions pack` resolves its SOURCE_DIRECTORY against the current
# directory, so a documented `cd .. && gnome-extensions pack gnome-extension`
# only works when you were already inside this directory. Run it from anywhere
# else and it fails with "Missing extension.js in extension pack", which reads
# like the file is missing rather than like you are in the wrong place.
#
# So resolve our own location instead, and this works from any directory.
#
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname -- "$here")
out=${1:-/tmp}

command -v gnome-extensions >/dev/null || {
    echo "gnome-extensions not found; is this GNOME?" >&2; exit 1; }
[ -f "$root/LICENSE" ] || {
    echo "No LICENSE at $root -- extensions.gnome.org expects one." >&2; exit 1; }

mkdir -p -- "$out"
gnome-extensions pack "$here" --force \
    --extra-source="$root/LICENSE" \
    --out-dir="$out"

uuid=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["uuid"])' \
       "$here/metadata.json")
zip="$out/$uuid.shell-extension.zip"

printf '\nBuilt %s\n\n' "$zip"
unzip -l "$zip"
printf '\nUpload it at https://extensions.gnome.org/upload/\n'
