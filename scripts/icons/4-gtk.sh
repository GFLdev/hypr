#!/bin/sh
# 4 - GTK apps: gsettings (what GTK reads on Wayland) and settings.ini (X, fallback)
set -eu
. "$(dirname "$0")/common.sh"
theme_installed

schema=org.gnome.desktop.interface
if command -v gsettings >/dev/null && gsettings list-keys $schema >/dev/null 2>&1; then
    for kv in "icon-theme '$THEME'" "cursor-theme '$THEME'" "cursor-size $CURSOR_SIZE"; do
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
done
