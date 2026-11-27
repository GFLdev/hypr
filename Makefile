# Every variable can be overridden on the command line, for example:
#   make icons CURSOR_SIZE=32
#
# Works with both FreeBSD make (bmake) and gmake.

# Settings

THEME        ?= MonoIcons
CURSOR_SIZE  ?= 24
COLOR_SCHEME ?= dark
SCRIPTS_DIR  ?= scripts/icons
SCRIPT_ENV   ?= THEME=$(THEME) CURSOR_SIZE=$(CURSOR_SIZE) COLOR_SCHEME=$(COLOR_SCHEME)

HYPRCTL      ?= hyprctl
HYPRLAUNCHER ?= hyprlauncher
HYPRPAPER    ?= hyprpaper

.DEFAULT_GOAL := help

##@ General

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} \
		/^##@/ {printf "\n%s\n", substr($$0, 5)} \
		/^[a-z0-9-]+:.*## / {printf "  make %-20s %s\n", $$1, $$2}' Makefile

##@ Icons

.PHONY: icons
icons: icons-install icons-hyprland icons-x icons-gtk icons-qt ## Install the icon theme and apply it everywhere

.PHONY: icons-install
icons-install: ## Download THEME into ~/.icons (skipped when already at upstream's latest commit)
	$(SCRIPT_ENV) $(SCRIPTS_DIR)/1-install.sh

.PHONY: icons-reinstall
icons-reinstall: ## Download THEME again, even when up to date
	$(SCRIPT_ENV) $(SCRIPTS_DIR)/1-install.sh -f

.PHONY: icons-hyprland
icons-hyprland: ## Apply the cursor, hyprtoolkit icons and app icons to Hyprland
	$(SCRIPT_ENV) $(SCRIPTS_DIR)/2-hyprland.sh

.PHONY: icons-x
icons-x: ## Apply the cursor and icons to X apps (~/.icons/default, ~/.Xresources)
	$(SCRIPT_ENV) $(SCRIPTS_DIR)/3-x.sh

.PHONY: icons-gtk
icons-gtk: ## Apply the cursor, icons and COLOR_SCHEME to GTK apps (gsettings, settings.ini)
	$(SCRIPT_ENV) $(SCRIPTS_DIR)/4-gtk.sh

.PHONY: icons-qt
icons-qt: ## Make Qt apps follow the GTK settings (run icons-gtk first)
	$(SCRIPT_ENV) $(SCRIPTS_DIR)/5-qt.sh

##@ Theme

.PHONY: dark
dark: ## Switch GTK and Qt apps to the dark color scheme
	$(MAKE) icons-gtk COLOR_SCHEME=dark

.PHONY: light
light: ## Switch GTK and Qt apps to the light color scheme
	$(MAKE) icons-gtk COLOR_SCHEME=light

##@ Hyprland

.PHONY: reload
reload: ## Reload hyprland.lua and show config errors
	$(HYPRCTL) reload
	$(HYPRCTL) configerrors

.PHONY: errors
errors: ## Show config errors
	$(HYPRCTL) configerrors

.PHONY: launcher
launcher: ## Restart the hyprlauncher daemon (picks up hyprtoolkit.conf and icon changes)
	-pkill -x $(HYPRLAUNCHER)
	sleep 0.3
	$(HYPRLAUNCHER) -d >/dev/null 2>&1 &

.PHONY: lock
lock: ## Lock the screen with hyprlock (same as SUPER + X)
	pgrep -x hyprlock >/dev/null || hyprlock

.PHONY: wallpaper
wallpaper: ## Restart hyprpaper (picks up hyprpaper.conf changes)
	-pkill -x $(HYPRPAPER)
	sleep 0.3
	$(HYPRPAPER) >/dev/null 2>&1 &
