# Magister GTK

GTK4 frontend (Vala) for the `Magister2 serve` local HTTP/JSON API.

## Dependencies

Debian/Ubuntu:

    sudo apt install valac meson ninja-build libgtk-4-dev libsoup-3.0-dev libjson-glib-dev

Fedora:

    sudo dnf install vala meson gtk4-devel libsoup3-devel json-glib-devel

## Build & run

    meson setup build
    ninja -C build
    ./build/magister-gtk

## Use

1. Start the backend in a terminal with a fixed key:

       MAGISTER_API_KEY=geheim ./Magister2 -- "RSG Pantarijn" <leerlingnummer> serve

2. Open the app, click the gear icon, enter `http://127.0.0.1:5075` and your API key.
   Settings are saved in `~/.config/magister-gtk/config.ini`.

Tabs: Afspraken, Berichten, Cijfers, Studiewijzers. Attachments and study-guide
files appear as download buttons in the detail pane and are saved to your
Downloads folder. Every detail view has an expandable "Ruwe JSON" section.
