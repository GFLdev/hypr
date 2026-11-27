#!/bin/sh
# 3 - X apps (XWayland and X sessions): the "default" theme that libXcursor and
#     icon lookups fall back to, plus Xcursor resources.
set -eu
. "$(dirname "$0")/common.sh"
theme_installed

write_file "$ICONS_DIR/default/index.theme" "[Icon Theme]
Inherits=$THEME"

set_line "$HOME/.Xresources" '^Xcursor\.theme:' "Xcursor.theme: $THEME"
set_line "$HOME/.Xresources" '^Xcursor\.size:' "Xcursor.size: $CURSOR_SIZE"

# Running X server (XWayland under Hyprland). Only these two resources are
# merged; the rest of ~/.Xresources is left to xinitrc.
if [ -n "${DISPLAY:-}" ] && command -v xrdb >/dev/null; then
    printf 'Xcursor.theme: %s\nXcursor.size: %s\n' "$THEME" "$CURSOR_SIZE" | xrdb -merge -nocpp
    log "merged Xcursor resources into $DISPLAY"
fi
