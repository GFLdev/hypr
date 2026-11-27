#!/bin/sh
# 2 - Hyprland: cursor (hl.env in hyprland.lua), icon theme for hyprtoolkit apps
#     (hyprlauncher) and the monochrome app icons MonoIcons lacks (icons/hicolor).
set -eu
. "$(dirname "$0")/common.sh"
theme_installed

# Cursor. MonoIcons is XCursor only, so hyprcursor falls back to it.
hypr_env XCURSOR_THEME "$THEME"
hypr_env XCURSOR_SIZE "$CURSOR_SIZE"
hypr_env HYPRCURSOR_THEME "$THEME"
hypr_env HYPRCURSOR_SIZE "$CURSOR_SIZE"

# hyprtoolkit
set_line "$HYPR_DIR/hyprtoolkit.conf" '^icon_theme *=' "icon_theme = $THEME"

# App icons: the user hicolor theme, which every icon theme falls back to.
# index.theme is the system one, so GTK still sees all of hicolor's sizes.
overlay=$DATA_ICONS_DIR/hicolor
link /usr/local/share/icons/hicolor/index.theme "$overlay/index.theme"
for icon in "$HYPR_DIR"/icons/hicolor/scalable/apps/*.svg; do
    if [ -e "$icon" ]; then link "$icon" "$overlay/scalable/apps/${icon##*/}"; fi
done
# Drop links to icons removed from the repo
for l in "$overlay"/scalable/apps/*.svg; do
    if [ -L "$l" ] && [ ! -e "$l" ]; then
        rm "$l" && log "removed dangling $l"
    fi
done

# Apply to the running session
if hypr_running; then
    hypr_reload
    hyprctl setcursor "$THEME" "$CURSOR_SIZE" >/dev/null && log "set cursor"

    # hyprtoolkit reads the icon theme once, at startup
    if pgrep -x hyprlauncher >/dev/null; then
        pkill -x hyprlauncher
        sleep 0.3
        (hyprlauncher -d >/dev/null 2>&1 &)
        log "restarted hyprlauncher"
    fi
fi
