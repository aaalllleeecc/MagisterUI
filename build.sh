#!/usr/bin/env bash
# Clean all old build output, then build ./magister-gtk with meson.
set -euo pipefail
cd "$(dirname "$0")"

PKGS="gtk4 libsoup-3.0 json-glib-1.0"
SRC="src/main.vala"
OUT="magister-gtk"

# clear old build stuff
rm -rf build "$OUT" src/*.c c-fallback/"$OUT"

for tool in valac meson ninja glib-compile-resources; do
    command -v "$tool" >/dev/null || { echo "$tool not found"; exit 1; }
done
for p in $PKGS; do
    pkg-config --exists "$p" || { echo "missing dev package: $p"; exit 1; }
done

# must be the Vala file, not the C# source
head -n 5 "$SRC" | grep -q '^using Gtk;' || { echo "$SRC is not the Vala GUI (no 'using Gtk;' at top)"; exit 1; }

meson setup build
meson compile -C build
cp "build/$OUT" "./$OUT"
echo "built ./$OUT"