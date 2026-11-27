#!/bin/sh
# 1 - Download MonoIcons (github.com/witalihirsch/Mono-icon-theme) into ~/.icons
#     and expose it in ~/.local/share/icons, where hyprtoolkit looks.
#     Skips the download when upstream's latest commit is already installed; -f forces it.
set -eu
. "$(dirname "$0")/common.sh"

force=0
if [ "${1:-}" = -f ]; then force=1; fi

dest=$ICONS_DIR/$THEME
stamp=$dest/.upstream-commit

rev=$(git ls-remote "https://github.com/$REPO" "refs/heads/$BRANCH" | cut -f1)
[ -n "$rev" ] || die "can't get the latest commit of github.com/$REPO"

if [ $force -eq 0 ] && [ "$(cat "$stamp" 2>/dev/null)" = "$rev" ]; then
    log "$THEME already at $rev"
else
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    log "downloading $REPO@$rev"
    url=https://codeload.github.com/$REPO/tar.gz/$rev
    if command -v fetch >/dev/null; then
        fetch -q -o "$tmp/src.tar.gz" "$url"
    else
        curl -fsSL -o "$tmp/src.tar.gz" "$url"
    fi

    mkdir "$tmp/$THEME"
    tar -xzf "$tmp/src.tar.gz" -C "$tmp/$THEME" --strip-components 2 \
        "${REPO#*/}-$rev/$REPO_DIR"
    [ -f "$tmp/$THEME/index.theme" ] || die "no $REPO_DIR/index.theme in the download"
    printf '%s\n' "$rev" >"$tmp/$THEME/.upstream-commit"

    # Swap in the new copy, so a failed download never leaves a broken theme
    mkdir -p "$ICONS_DIR"
    rm -rf "$dest.old"
    if [ -e "$dest" ]; then mv "$dest" "$dest.old"; fi
    mv "$tmp/$THEME" "$dest"
    rm -rf "$dest.old"
    log "installed $dest"

    if command -v gtk-update-icon-cache >/dev/null; then
        gtk-update-icon-cache -q -f -t "$dest" && log "updated icon cache"
    fi
fi

# hyprtoolkit only searches $XDG_DATA_HOME/icons and $XDG_DATA_DIRS, not ~/.icons
link "$dest" "$DATA_ICONS_DIR/$THEME"
