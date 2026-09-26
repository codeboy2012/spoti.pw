#!/usr/bin/env python3
"""Optional system-tray icon for serverctl on Linux (and macOS).

Uses the freedesktop StatusNotifier/AppIndicator API via PyGObject when the
desktop environment supports it (GNOME with AppIndicator extension, KDE,
XFCE, Cinnamon, MATE...). Installs nothing itself; see README for the two
packages that provide the backend on common distros.

    python3 scripts/server-control/tray.py
"""

import os
import subprocess
import sys
import threading

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

try:
    gi.require_version("AyatanaAppIndicator3", "0.1")
    from gi.repository import AyatanaAppIndicator3 as AppIndicator  # noqa: E402
except (ValueError, ImportError):
    try:
        gi.require_version("AppIndicator3", "0.1")
        from gi.repository import AppIndicator3 as AppIndicator  # noqa: E402
    except (ValueError, ImportError):
        AppIndicator = None

HERE = os.path.dirname(os.path.abspath(__file__))
SERVERCTL = os.path.join(HERE, "serverctl")

GREEN = "#2ecc71"
RED = "#e74c3c"

# 16x16 solid-dot icons drawn inline so no asset files are needed
SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">' \
      '<circle cx="8" cy="8" r="6" fill="{color}"/></svg>'


def run_ctl(*args):
    return subprocess.run([sys.executable, SERVERCTL, *args],
                          capture_output=True, text=True, timeout=30)


def is_running(server=""):
    out = run_ctl("status", server).stdout if server else run_ctl("status").stdout
    return "RUNNING" in out


def write_icon(color):
    path = os.path.join("/tmp", f"pweevee-serverctl-{color.lstrip('#')}.svg")
    with open(path, "w") as f:
        f.write(SVG.format(color=color))
    return path


class TrayApp:
    def __init__(self):
        self.icon = AppIndicator.Indicator.new(
            "pweevee-serverctl", "serverctl", AppIndicator.IndicatorCategory.APPLICATION_STATUS)
        self.icon.set_status(AppIndicator.IndicatorStatus.ACTIVE)
        self.running_icon = write_icon(RED)
        self.icon.set_icon_full(self.running_icon, "servers stopped")

        self.menu = Gtk.Menu()
        self._add(f"🟢 Start Server", self.on_start)
        self._add(f"🔴 Stop Server", self.on_stop)
        self._add(f"🔄 Restart Server", self.on_restart)
        self._add("📊 Server Status", self.on_status, sensitive=False)
        self._add("⚙️ Settings", self.on_settings)
        self._add("❌ Exit", self.on_exit)
        self.menu.show_all()
        self.icon.set_menu(self.menu)

        self._refresh()

    def _add(self, label, callback, sensitive=True):
        item = Gtk.MenuItem(label=label)
        item.connect("activate", callback)
        item.set_sensitive(sensitive)
        self.menu.append(item)

    def _refresh(self):
        running = is_running()
        path = write_icon(GREEN if running else RED)
        self.icon.set_icon_full(path, "servers running" if running else "servers stopped")

        def apply():
            items = list(self.menu.get_children())
            items[0].set_sensitive(not running)   # start
            items[1].set_sensitive(running)       # stop
            items[3].set_sensitive(True)          # status label refresh
            items[3].set_label("📊 " + ("Server Status: running" if running else "Server Status: stopped"))
        self.menu.show_all()
        apply()

    def _busy(self, label):
        item = list(self.menu.get_children())[3]
        item.set_label("⏳ " + label)

    def on_start(self, _):
        self._busy("starting…")
        threading.Thread(target=lambda: (run_ctl("start"), GLib.idle_add(self._refresh))).start()

    def on_stop(self, _):
        self._busy("stopping…")
        threading.Thread(target=lambda: (run_ctl("stop"), GLib.idle_add(self._refresh))).start()

    def on_restart(self, _):
        self._busy("restarting…")
        threading.Thread(target=lambda: (run_ctl("restart"), GLib.idle_add(self._refresh))).start()

    def on_status(self, _):
        out = run_ctl("status").stdout.strip()
        dialog = Gtk.MessageDialog(
            message_type=Gtk.MessageType.INFO, buttons=Gtk.ButtonsType.OK, text="Server status")
        dialog.format_secondary_text(out or "no servers configured")
        dialog.run()
        dialog.destroy()

    def on_settings(self, _):
        cfg = os.environ.get("SERVERCTL_CONFIG",
                             os.path.join(HERE, "config.json"))
        for editor in ("xdg-open", "gedit", "mousepad", "kate"):
            if subprocess.run(["sh", "-c", f"command -v {editor}"], capture_output=True).returncode == 0:
                subprocess.Popen([editor, cfg])
                return
        print("config file:", cfg)

    def on_exit(self, _):
        Gtk.main_quit()


def main():
    if AppIndicator is None:
        print("tray.py: no AppIndicator backend found.")
        print("  Debian/Ubuntu: sudo apt install gir1.2-ayatanappindicator3-0.1")
        print("  Fedora:        sudo dnf install libappindicator-gtk3")
        print("  Arch:          pacman -S libayatana-appindicator")
        print("The CLI still works: ./serverctl status|start|stop|restart")
        return 1
    from gi.repository import GLib
    globals()["GLib"] = GLib
    TrayApp()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
