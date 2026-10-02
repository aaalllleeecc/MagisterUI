#!/usr/bin/env bash
# Install the app icon and a .desktop file for the current user,
# so the taskbar / dock shows the Magister icon.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"

APP_ID="nl.magister.gtk"
NAME="Magister"
SRC_IMG="Resources/image.jpg"

ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
APP_DIR="$HOME/.local/share/applications"

# What the launcher starts: run.sh if it exists (it sets the env vars), else the binary
if [ -x "$ROOT/run.sh" ]; then
    EXEC="$ROOT/run.sh"
elif [ -x "$ROOT/magister-gtk" ]; then
    EXEC="$ROOT/magister-gtk"
else
    echo "Neither ./run.sh nor ./magister-gtk is executable. Run ./build.sh and chmod +x run.sh first."
    exit 1
fi

[ -f "$SRC_IMG" ] || { echo "missing $SRC_IMG"; exit 1; }

mkdir -p "$ICON_DIR" "$APP_DIR"

# icon: the taskbar needs a PNG, so convert the JPG
if command -v magick >/dev/null; then
    magick "$SRC_IMG" -resize 256x256 "$ICON_DIR/$APP_ID.png"
elif command -v convert >/dev/null; then
    convert "$SRC_IMG" -resize 256x256 "$ICON_DIR/$APP_ID.png"
else
    echo "ImageMagick not found (need 'magick' or 'convert') to turn the JPG into a PNG"
    exit 1
fi

# desktop file (its name must match the app id in Gtk.Application)
cat > "$APP_DIR/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$NAME
Comment=Magister client
Exec=$EXEC
Icon=$APP_ID
Terminal=false
Categories=Education;
StartupWMClass=$APP_ID
EOF
chmod +x "$APP_DIR/$APP_ID.desktop"

# refresh caches (ignore errors if the tools are missing)
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
update-desktop-database "$APP_DIR" 2>/dev/null || true

echo "installed:"
echo "  $ICON_DIR/$APP_ID.png"
echo "  $APP_DIR/$APP_ID.desktop  (Exec=$EXEC)"
echo "Restart the app. If the icon doesn't change, log out and back in."