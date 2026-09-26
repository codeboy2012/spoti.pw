PwEevee server control — Windows tray/CLI and Linux serverctl for the local
preview servers. Start / stop / restart / status; fully detached launches.

# Windows
1. Build (only after editing ServerTray.cs; exes are not committed):
       scripts\server-control\win\build.cmd
2. Run scripts\server-control\win\ServerTray.exe  → tray icon in the `^` area
   (menu: Start / Stop / Restart / Status / Run at startup / Settings / Exit).
   Or use the console:  scripts\server-control\win\ServerCtl.exe status|start|stop|restart

# Linux / macOS
1. CLI:   scripts/server-control/serverctl status|start|stop|restart
2. Service (systemd user):  serverctl install|uninstall website
3. Optional tray icon:      python3 scripts/server-control/tray.py
   (needs gir1.2-ayatanappindicator3-0.1 on Debian/Ubuntu; see README.md)

Servers are defined in scripts/server-control/config.json. Logs land in
.freebuff/<server>.log[.err].
