# Server control — tray + CLI for the PwEevee local servers

Start / stop / restart / status for every server listed in
[`config.json`](config.json) (currently the static website preview server on
port 4173), from a Windows system-tray icon, a Linux tray icon, or a plain
command line. Everything runs detached: servers survive closed terminals and
reboots of the tool.

```
scripts/server-control/
├── config.json              the single list of servers (ports, commands, logs)
├── serverctl                cross-platform CLI (bash; Linux/macOS, works in Git Bash)
├── tray.py                  optional Linux tray icon (GTK AppIndicator)
├── win/
│   ├── ServerTray.cs        single C# source for BOTH Windows exes
│   ├── build.cmd            compiles with the in-box csc.exe — no SDK needed
│   ├── ServerTray.exe       tray app (winexe: never opens a console)
│   └── ServerCtl.exe        console CLI (same commands as serverctl)
└── linux/
    └── pweevee-tray.service systemd user unit template for tray.py
```

## Windows

Build once (only needed after changing `ServerTray.cs`; the built exes are not
committed):

```bat
scripts\server-control\win\build.cmd
```

**Tray app** — double-click `ServerTray.exe` (or `ServerCtl.exe tray`).
A dot appears in the notification area (the `^` overflow menu if hidden):

- 🟢 **Start Server** / 🔴 **Stop Server** / 🔄 **Restart Server** — enabled
  according to the live port state; balloon tips report the result
- 📊 **Server Status** — state, port and pid for every configured server
- ⚙ **Run at startup** — persists in `HKCU\...\Run` so the tray returns at login
- ⚙ **Settings** — opens `config.json` in Notepad
- ❌ **Exit**

Icon color tracks state live: green = running, red = stopped. Idle footprint is
a single ~30 MB WinForms process with no timers or polling — it wakes only when
you open the menu.

**CLI** (same operations in any terminal):

```
ServerCtl.exe status          STOPPED / LISTENING / RUNNING + pid
ServerCtl.exe start           detached launch, waits until the port answers
ServerCtl.exe stop            kills the listener on the port (taskkill /T /F)
ServerCtl.exe restart
```

Exit codes: `0` success / up, `1` failure, `3` down (script-friendly).

**How detached launch works:** the server is created by the WMI service
(`Win32_Process.Create`), not as a child of the calling process — so it inherits
no console pipes and no job, cannot hold a terminal open, and survives the tool
exiting. stdout/stderr go to the log files configured in `config.json`
(`.freebuff/website-server.log[.err]` here). Stop finds the pid by listening
port via `netstat -ano`, so it also stops servers started any other way.

## Linux / macOS

```
scripts/server-control/serverctl status | start | stop | restart
```

- `start` uses `setsid nohup … </dev/null >log 2>err &` — fully detached from
  the terminal and session, same idea as the Windows WMI launch
- `stop` kills the recorded pid plus whatever actually listens on the port
  (`ss`/`lsof`), escalating to SIGKILL if needed
- `status` prints one line per server and exits non-zero when down

**Run as a service** (Linux, systemd): keep it alive across logins and boots —

```
scripts/server-control/serverctl install website     # installs ~/.config/systemd/user/pweevee-website.service
scripts/server-control/serverctl uninstall website
```

**Optional tray icon** — where the desktop environment provides a
StatusNotifier/AppIndicator area (KDE, XFCE, Cinnamon, MATE, GNOME with the
AppIndicator extension):

```bash
sudo apt install gir1.2-ayatanappindicator3-0.1 python3-gi   # Debian/Ubuntu
python3 scripts/server-control/tray.py
```

Same menu as Windows (start/stop/restart/status/settings/exit), live icon
color, and a status dialog. Without the backend, `tray.py` prints install
hints and the CLI keeps working. On macOS the CLI works as-is; a tray icon
would need a menu-bar app framework and is out of scope here.

## Adding a server

Append to `config.json`:

```json
{
  "name": "myserver",
  "description": "what it is",
  "port": 8080,
  "httpProbe": "http://127.0.0.1:8080/",
  "windows": {
    "exe": "C:\\path\\to\\server.exe", "args": ["--port", "8080"],
    "workingDir": "<REPO_ROOT>", "logFile": "<REPO_ROOT>\\.freebuff\\myserver.log",
    "errFile": "<REPO_ROOT>\\.freebuff\\myserver.log.err"
  },
  "linux": {
    "exe": "python3", "args": ["-m", "http.server", "8080"],
    "workingDir": "<REPO_ROOT>", "logFile": ".freebuff/myserver.log",
    "errFile": ".freebuff/myserver.log.err"
  }
}
```

`<REPO_ROOT>` is replaced with the checkout root at load time. State probes are
raw TCP connects (works for any protocol); `httpProbe` adds the richer
`RUNNING` state when the port serves HTTP.
