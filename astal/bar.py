#!/usr/bin/env python3
# Status bar: a transparent bar at the top of every connected monitor, with
# that monitor's workspaces, the playing media (main monitor only), the battery
# (laptops only) and a clock.
# Bars come and go with the monitors (HDMI plugged in or out).
#
# Needs the Astal3 (lib/astal/gtk3), AstalHyprland (lib/hyprland) and
# AstalMpris (lib/mpris) libraries from https://github.com/aylur/astal, plus
# py-gobject. Players are only seen inside a D-Bus session (dbus-run-session).

import math
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Astal", "3.0")
gi.require_version("AstalHyprland", "0.1")
gi.require_version("AstalMpris", "0.1")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
gi.require_version("Pango", "1.0")

import cairo
from gi.repository import Astal, Gdk, GdkPixbuf, GLib, Gtk, Pango
from gi.repository import AstalHyprland as Hyprland
from gi.repository import AstalMpris as Mpris

STYLE = Path(__file__).resolve().parent / "style.css"
CLOCK_FORMAT = "%a %d %b  %H:%M"
MAIN_MONITOR = "HDMI-A-1"  # as in hyprland.lua
DISC_RPM = 100 / 3  # an LP's 33⅓

# Addresses of windows that asked for attention, until they get focused.
# Shared by every bar; AstalHyprland only gives the "urgent" event, no state.
URGENT = set()


def hypr_monitor(gdkmonitor):
    """The Hyprland monitor at the same position as this GDK monitor."""
    geometry = gdkmonitor.get_geometry()
    for monitor in Hyprland.get_default().get_monitors():
        if (monitor.get_x(), monitor.get_y()) == (geometry.x, geometry.y):
            return monitor
    return None


def is_main(monitor):
    """MAIN_MONITOR, or whichever monitor is left while it is unplugged."""
    names = [m.get_name() for m in Hyprland.get_default().get_monitors()]
    return monitor.get_name() == MAIN_MONITOR or MAIN_MONITOR not in names


def connect_while_alive(widget, gobject, signals, callback):
    """Connect callback to gobject's signals until widget is destroyed."""
    ids = [gobject.connect(signal, callback) for signal in signals]
    widget.connect("destroy", lambda *_: [gobject.disconnect(i) for i in ids])


class Workspaces(Gtk.Box):
    """This monitor's workspaces by name; click one to switch to it."""

    def __init__(self, gdkmonitor):
        super().__init__(halign=Gtk.Align.START)
        Astal.widget_set_class_names(self, ["Workspaces"])
        self.gdkmonitor = gdkmonitor
        connect_while_alive(
            self,
            Hyprland.get_default(),
            [
                "notify::monitors",
                "notify::workspaces",
                "notify::focused-workspace",
                "notify::focused-client",
                "notify::clients",
                "client-moved",
            ],
            self.sync,
        )
        connect_while_alive(self, Hyprland.get_default(), ["urgent"], self.urgent)
        self.sync()

    def urgent(self, _, client):
        URGENT.add(client.get_address())
        self.sync()

    def sync(self, *_):
        focused = Hyprland.get_default().get_focused_client()
        if focused is not None:
            URGENT.discard(focused.get_address())

        for child in self.get_children():
            child.destroy()

        monitor = hypr_monitor(self.gdkmonitor)
        if monitor is None:
            return

        active = monitor.get_active_workspace()
        workspaces = [
            ws
            for ws in Hyprland.get_default().get_workspaces()
            if ws.get_id() > 0 and ws.get_monitor() == monitor  # no special ones
        ]
        for ws in sorted(workspaces, key=lambda ws: ws.get_id()):
            self.add(self.button(ws, ws == active))

    def button(self, ws, active):
        classes = []
        if active:
            classes.append("active")
        if ws.get_clients():
            classes.append("occupied")
        if any(c.get_address() in URGENT for c in ws.get_clients()):
            classes.append("urgent")

        button = Gtk.Button(visible=True, label=ws.get_name())
        Astal.widget_set_class_names(button, classes)
        # Not ws.focus(): it sends "dispatch workspace N", which the Lua config rejects
        button.connect(
            "clicked",
            lambda *_: Hyprland.get_default().message(f"dispatch hl.dsp.focus({{ workspace = {ws.get_id()} }})"),
        )
        return button


def active_player():
    """The playing player, else the first paused one, else None."""
    players = Mpris.get_default().get_players()
    for status in (Mpris.PlaybackStatus.PLAYING, Mpris.PlaybackStatus.PAUSED):
        for player in players:
            if player.get_playback_status() == status:
                return player
    return None


class Disc(Gtk.DrawingArea):
    """Cover art as a record with a hole in the middle, turning while playing.
    Drawn with cairo, since GTK3 CSS can't rotate."""

    def __init__(self):
        # Size and margin set here: GTK3 CSS ignores them on a DrawingArea
        super().__init__(visible=True, valign=Gtk.Align.CENTER, margin_end=12)
        self.set_size_request(20, 20)
        self.path = None
        self.pixbuf = None  # loaded on first draw, once the size is known
        self.angle = 0.0
        self.tick = None
        self.last = None

    def set_art(self, path):
        if path != self.path:
            self.path, self.pixbuf = path, None
            self.queue_draw()

    def set_playing(self, playing):
        if playing and self.tick is None:
            self.last = None
            self.tick = self.add_tick_callback(self.turn)
        elif not playing and self.tick is not None:
            self.remove_tick_callback(self.tick)
            self.tick = None

    def turn(self, _, clock):
        now = clock.get_frame_time()  # µs
        if self.last is not None:
            self.angle += (now - self.last) / 60e6 * DISC_RPM * 2 * math.pi
        self.last = now
        self.queue_draw()
        return GLib.SOURCE_CONTINUE

    def do_draw(self, cr):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        r = min(w, h) / 2
        cr.translate(w / 2, h / 2)
        cr.arc(0, 0, r, 0, 2 * math.pi)
        cr.new_sub_path()
        cr.arc(0, 0, r * 0.2, 0, 2 * math.pi)
        cr.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
        cr.clip()

        if self.path and self.pixbuf is None:
            size = round(2 * r * self.get_scale_factor())
            try:
                self.pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(self.path, size, size, True)
            except GLib.Error:
                self.path = None
        cr.rotate(self.angle)
        if self.pixbuf is None:  # no art: a white disc, with a line to show it turning
            cr.set_source_rgb(1, 1, 1)
            cr.paint()
            cr.set_source_rgba(0, 0, 0, 0.6)
            cr.set_line_width(1.5)
            cr.move_to(0, 0)
            cr.line_to(0, -r)
            cr.stroke()
        else:
            pw, ph = self.pixbuf.get_width(), self.pixbuf.get_height()
            scale = 2 * r / min(pw, ph)  # cover, cropping the long side
            cr.scale(scale, scale)
            Gdk.cairo_set_source_pixbuf(cr, self.pixbuf, -pw / 2, -ph / 2)
            cr.paint()


class Media(Gtk.Box):
    """The active media player: cover art on a disc, then "Artist - Title".
    Only on the main monitor, hidden when nothing is playing or paused."""

    def __init__(self, gdkmonitor):
        super().__init__(no_show_all=True)
        Astal.widget_set_class_names(self, ["Media"])
        self.gdkmonitor = gdkmonitor

        self.cover = Disc()
        self.label = Gtk.Label(visible=True, ellipsize=Pango.EllipsizeMode.END, max_width_chars=60)
        self.add(self.cover)
        self.add(self.label)

        mpris = Mpris.get_default()
        connect_while_alive(self, mpris, ["player-added"], self.watch)
        connect_while_alive(self, mpris, ["player-closed"], self.sync)
        connect_while_alive(self, Hyprland.get_default(), ["notify::monitors"], self.sync)
        for player in mpris.get_players():
            self.watch(mpris, player)
        self.sync()

    def watch(self, _, player):
        signals = ["notify::playback-status", "notify::artist", "notify::title", "notify::cover-art"]
        connect_while_alive(self, player, signals, self.sync)
        self.sync()

    def sync(self, *_):
        monitor = hypr_monitor(self.gdkmonitor)
        player = active_player() if monitor is not None and is_main(monitor) else None
        self.set_visible(player is not None)
        if player is None:
            return

        self.label.set_label(" - ".join(filter(None, [player.get_artist(), player.get_title()])))
        self.cover.set_art(player.get_cover_art())
        self.cover.set_playing(player.get_playback_status() == Mpris.PlaybackStatus.PLAYING)


def battery():
    """(percent, charging) from FreeBSD's ACPI battery, or None without one."""
    try:
        out = subprocess.run(
            ["sysctl", "-n", "hw.acpi.battery.units", "hw.acpi.battery.life", "hw.acpi.battery.state"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):  # no such sysctl: a desktop
        return None
    units, life, state = map(int, out.split())
    if units == 0:  # laptop with the battery taken out
        return None
    return life, bool(state & 2)  # state bit 2 = charging


class Battery(Gtk.Label):
    """Battery charge, on laptops (Bar leaves it out when battery() is None)."""

    def __init__(self):
        super().__init__()
        Astal.widget_set_class_names(self, ["Battery"])
        self.sync()
        source = GLib.timeout_add_seconds(30, self.sync)
        self.connect("destroy", lambda *_: GLib.source_remove(source))

    def sync(self):
        status = battery()
        if status is not None:
            life, charging = status
            self.set_label(f"{'CHR' if charging else 'BAT'} {life}%")
        return GLib.SOURCE_CONTINUE


class Clock(Gtk.Label):
    def __init__(self):
        super().__init__(halign=Gtk.Align.END)
        Astal.widget_set_class_names(self, ["Clock"])
        self.sync()
        source = GLib.timeout_add_seconds(1, self.sync)
        self.connect("destroy", lambda *_: GLib.source_remove(source))

    def sync(self):
        self.set_label(GLib.DateTime.new_now_local().format(CLOCK_FORMAT))
        return GLib.SOURCE_CONTINUE


class Bar(Astal.Window):
    def __init__(self, gdkmonitor):
        super().__init__(
            gdkmonitor=gdkmonitor,
            namespace="astal-bar",
            anchor=Astal.WindowAnchor.TOP
            | Astal.WindowAnchor.LEFT
            | Astal.WindowAnchor.RIGHT,
            exclusivity=Astal.Exclusivity.EXCLUSIVE,
        )
        Astal.widget_set_class_names(self, ["Bar"])

        end = Gtk.Box(halign=Gtk.Align.END)
        if battery() is not None:
            end.add(Battery())
        end.add(Clock())

        self.add(
            Astal.CenterBox(
                start_widget=Workspaces(gdkmonitor),
                center_widget=Media(gdkmonitor),
                end_widget=end,
            )
        )
        self.show_all()


class App(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="dev.gfl.astal.bar")
        self.bars = {}

    def do_activate(self):
        if self.bars:  # already running, nothing to do
            return

        provider = Gtk.CssProvider()
        provider.load_from_path(str(STYLE))
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
        )

        display = Gdk.Display.get_default()
        display.connect("monitor-added", lambda _, monitor: self.add_bar(monitor))
        display.connect("monitor-removed", lambda _, monitor: self.remove_bar(monitor))
        for i in range(display.get_n_monitors()):
            self.add_bar(display.get_monitor(i))

        self.hold()  # keep running while every monitor is unplugged

    def add_bar(self, gdkmonitor):
        bar = Bar(gdkmonitor)
        self.add_window(bar)
        self.bars[gdkmonitor] = bar

    def remove_bar(self, gdkmonitor):
        bar = self.bars.pop(gdkmonitor, None)
        if bar is not None:
            bar.destroy()


if __name__ == "__main__":
    GLib.set_prgname("astal-bar")
    sys.exit(App().run(sys.argv))
