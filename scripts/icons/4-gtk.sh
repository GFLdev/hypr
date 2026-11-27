#!/bin/sh
# 4 - GTK apps: gsettings (what GTK reads on Wayland) and settings.ini (X, fallback).
#     Also the light/dark color scheme (COLOR_SCHEME), which Qt follows via 5-qt.sh.
set -eu
. "$(dirname "$0")/common.sh"
theme_installed

case $COLOR_SCHEME in
dark)
    gtk_theme=Adwaita-dark scheme=prefer-dark prefer_dark=1
    # GTK3 has the dark Adwaita built in but only as a variant, not a theme name,
    # so gsettings' gtk-theme can't select it. Same shim as gnome-themes-extra's.
    write_file "$DATA_THEMES_DIR/Adwaita-dark/gtk-3.0/gtk.css" \
        '@import url("resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css");'
    ;;
light) gtk_theme=Adwaita scheme=default prefer_dark=0 ;;
*) die "COLOR_SCHEME must be dark or light, not '$COLOR_SCHEME'" ;;
esac

schema=org.gnome.desktop.interface
if command -v gsettings >/dev/null && gsettings list-keys $schema >/dev/null 2>&1; then
    for kv in "icon-theme '$THEME'" "cursor-theme '$THEME'" "cursor-size $CURSOR_SIZE" \
        "gtk-theme '$gtk_theme'" "color-scheme '$scheme'"; do
        key=${kv%% *}
        value=${kv#* }
        if [ "$(gsettings get $schema "$key")" != "$value" ]; then
            gsettings set $schema "$key" "$value"
            log "gsettings $key = $value"
        fi
    done
else
    log "gsettings or the $schema schema missing, skipping (pkg install gsettings-desktop-schemas)" >&2
fi

for v in 3.0 4.0; do
    ini=$CONFIG_DIR/gtk-$v/settings.ini
    ini_set "$ini" Settings gtk-icon-theme-name "$THEME"
    ini_set "$ini" Settings gtk-cursor-theme-name "$THEME"
    ini_set "$ini" Settings gtk-cursor-theme-size "$CURSOR_SIZE"
    # The plain theme name: the variant comes from prefer-dark, no shim needed
    ini_set "$ini" Settings gtk-theme-name Adwaita
    ini_set "$ini" Settings gtk-application-prefer-dark-theme "$prefer_dark"
done
