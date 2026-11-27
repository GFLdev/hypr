#!/bin/sh
# 5 - Qt apps: Qt's gtk3 platform theme (part of qt6-base), so Qt takes the icon
#     and cursor theme from GTK's settings. Run 4-gtk.sh first.
set -eu
. "$(dirname "$0")/common.sh"
theme_installed

plugin=$(ls /usr/local/lib/qt*/plugins/platformthemes/libqgtk3.so 2>/dev/null | head -1)
[ -n "$plugin" ] || die "Qt gtk3 platform theme not found (pkg install qt6-base)"

if command -v gsettings >/dev/null &&
    [ "$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null)" != "'$THEME'" ]; then
    log "GTK icon theme isn't $THEME yet, Qt will follow it once 4-gtk.sh runs" >&2
fi

hypr_env QT_QPA_PLATFORMTHEME gtk3
hypr_reload
