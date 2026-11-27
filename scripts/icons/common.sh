# Shared by the icon scripts (sourced, not run). Override THEME / CURSOR_SIZE from the env.

THEME=${THEME:-MonoIcons}
CURSOR_SIZE=${CURSOR_SIZE:-24}

REPO=witalihirsch/Mono-icon-theme
BRANCH=main
REPO_DIR=MonoIcons # theme directory inside the repo

HYPR_DIR=$(cd "$(dirname "$0")/../.." && pwd -P)
ICONS_DIR=$HOME/.icons
DATA_ICONS_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/icons
CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}

log() { printf '%s: %s\n' "${0##*/}" "$*"; }
die() { log "$*" >&2; exit 1; }

# set_line FILE REGEX LINE [ANCHOR]
# Replace the first line matching REGEX (awk ERE) with LINE. Without a match,
# insert LINE after the last line matching ANCHOR, or append it.
# The file is only rewritten when its content changes.
set_line() {
    _file=$1
    mkdir -p "$(dirname "$_file")"
    [ -e "$_file" ] || : >"$_file"

    _tmp=$(mktemp)
    RE=$2 LINE=$3 ANCHOR=${4:-} awk '
        BEGIN { re = ENVIRON["RE"]; line = ENVIRON["LINE"]; anchor = ENVIRON["ANCHOR"] }
        { a[NR] = $0; if (!found && $0 ~ re) found = NR; if (anchor != "" && $0 ~ anchor) last = NR }
        END {
            if (found) a[found] = line
            for (i = 1; i <= NR; i++) { print a[i]; if (!found && i == last) print line }
            if (!found && !last) print line
        }' "$_file" >"$_tmp"

    if cmp -s "$_tmp" "$_file"; then
        rm -f "$_tmp"
    else
        cat "$_tmp" >"$_file" # keeps the file's mode and any symlink
        rm -f "$_tmp"
        log "set in $_file: $3"
    fi
}

# write_file FILE CONTENT: only rewrites FILE when CONTENT differs
write_file() {
    mkdir -p "$(dirname "$1")"
    if [ "$(cat "$1" 2>/dev/null)" != "$2" ]; then
        printf '%s\n' "$2" >"$1"
        log "wrote $1"
    fi
}

# link TARGET LINKNAME: symlink, refusing to replace a real file/directory
link() {
    if [ -e "$2" ] && [ ! -L "$2" ]; then
        log "skipping $2: exists and is not a symlink" >&2
        return 0
    fi
    if [ "$(readlink "$2" 2>/dev/null)" != "$1" ]; then
        mkdir -p "$(dirname "$2")"
        ln -sfn "$1" "$2"
        log "linked $2 -> $1"
    fi
}

# ini_set FILE SECTION KEY VALUE (single-section files like gtk settings.ini)
ini_set() {
    [ -e "$1" ] && grep -q "^\[$2\]" "$1" || set_line "$1" "^\[$2\]$" "[$2]"
    set_line "$1" "^$3 *=" "$3=$4"
}

# hypr_env NAME VALUE: hl.env() line in hyprland.lua, next to the other ones
hypr_env() {
    set_line "$HYPR_DIR/hyprland.lua" "^hl\.env\(\"$1\"," "hl.env(\"$1\", \"$2\")" '^hl\.env\('
}

hypr_running() {
    command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1
}

# Reload so new hl.env() values reach apps launched from now on
hypr_reload() {
    if hypr_running; then
        hyprctl reload >/dev/null && log "reloaded Hyprland"
    fi
}

theme_installed() {
    [ -f "$ICONS_DIR/$THEME/index.theme" ] || die "$THEME not in $ICONS_DIR, run 1-install.sh first"
}
