// ServerTray / ServerCtl — controller for the PwEevee local servers.
//
// Built from this single source into two exes by build.cmd:
//   ServerTray.exe  (winexe) — runs in the system tray / notification area,
//                              no console window, green/yellow/red icon,
//                              menu: Start / Stop / Restart / Status / Settings / Exit
//   ServerCtl.exe   (exe)    — console CLI for the same operations:
//                              status | start | stop | restart [server] | servers | tray
//
// Config: scripts/server-control/config.json (shared with the Linux serverctl
// counterpart conceptually; see the per-platform command blocks inside).
// Servers are launched detached (cmd.exe wrapper redirects stdout/stderr to log
// files and breaks the stdio pipe, so children outlive this process) and probed
// with raw TCP connects; the HTTP probe is optional and best-effort.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace PwEevee.ServerControl
{
    // Detached launch strategy (empirically the only reliable one when the parent
    // is a console/agent that waits on its whole process tree):
    //
    //   1. PREFERRED: in-process WMI — Win32_Process.Create via System.Management.
    //      The WMI service (WmiPrvSE.exe) creates the process in its own context:
    //      NOT a descendant of this process, no inherited handles, no shared job,
    //      no helper process that could linger.
    //      (powershell Start-Process and powershell Invoke-CimMethod helpers were
    //      both tried and hang when spawned from this environment.)
    //   2. FALLBACK: raw CreateProcessW with inheritHandles=false and, when the
    //      job object permits, CREATE_BREAKAWAY_FROM_JOB.
    internal static class Detach
    {
        // innerCommand is the cmd.exe payload AFTER /c, already fully quoted:
        //   "C:\path\server.exe" args > "log" 2> "err"
        public static int Launch(string cmdExe, string innerCommand, string workingDir)
        {
            string cmdLine = BuildCmdLine(cmdExe, innerCommand);
            int pid = ViaWmi(cmdLine, workingDir);
            if (pid != 0) return pid;
            return ViaCreateProcess(cmdLine, workingDir);
        }

        private static string BuildCmdLine(string cmdExe, string payload)
        {
            // Canonical /d /s /c form, verified against cmd's documented quote rules:
            //   - cmd.exe path left UNQUOTED (system32 — no spaces; quoting it makes
            //     WMI/CreateProcess strip the first quote of the line and corrupt
            //     the payload's own quoting)
            //   - payload enclosed in " ... " with spaces inside both ends, so the
            //     /s rule (strip first char + last quote) leaves the payload's own
            //     quotes intact: "C:\...\server.exe" args > "log" 2> "err"
            return cmdExe + " /d /s /c \" " + payload + " \"";
        }

        private static int ViaWmi(string cmdLine, string workingDir)
        {
            try
            {
                using (System.Management.ManagementClass mc =
                           new System.Management.ManagementClass("Win32_Process"))
                using (System.Management.ManagementBaseObject inParams = mc.GetMethodParameters("Create"))
                {
                    inParams["CommandLine"] = cmdLine;
                    inParams["CurrentDirectory"] = workingDir;
                    using (System.Management.ManagementBaseObject outParams =
                               mc.InvokeMethod("Create", inParams, null))
                    {
                        uint rc = Convert.ToUInt32(outParams["ReturnValue"]);
                        if (rc != 0)
                            throw new Exception("WMI Win32_Process.Create failed, code " + rc);
                        return (int)Convert.ToUInt32(outParams["ProcessId"]);
                    }
                }
            }
            catch
            {
                return 0;   // fall back to CreateProcess
            }
        }

        [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        private static extern bool CreateProcessW(string applicationName, string commandLine, IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles, uint creationFlags, IntPtr environment, string currentDirectory, ref STARTUPINFO startupInfo, out PROCESS_INFORMATION processInformation);

        [System.Runtime.InteropServices.DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);

        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        private struct STARTUPINFO
        {
            public uint cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public uint dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
            public ushort wShowWindow, cbReserved2;
            public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
        }

        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION
        {
            public IntPtr hProcess, hThread;
            public uint dwProcessId, dwThreadId;
        }

        private const uint CREATE_NO_WINDOW = 0x08000000;
        private const uint CREATE_BREAKAWAY_FROM_JOB = 0x01000000;

        private static int ViaCreateProcess(string cmdLine, string workingDir)
        {
            foreach (uint flags in new uint[] { CREATE_NO_WINDOW | CREATE_BREAKAWAY_FROM_JOB, CREATE_NO_WINDOW })
            {
                int pid = TryCreate(cmdLine, workingDir, flags);
                if (pid != 0) return pid;
            }
            return 0;
        }

        private static int TryCreate(string cmdLine, string workingDir, uint flags)
        {
            var si = new STARTUPINFO();
            si.cb = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(STARTUPINFO));
            PROCESS_INFORMATION pi;
            if (!CreateProcessW(null, cmdLine, IntPtr.Zero, IntPtr.Zero, false, flags, IntPtr.Zero, workingDir, ref si, out pi))
                return 0;
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            return (int)pi.dwProcessId;
        }
    }
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            try
            {
                return args.Length > 0 ? Cli.Run(args) : TrayApp.Run();
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "ServerTray", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
    }

    internal sealed class ServerConfig
    {
        public string Name;
        public string Description;
        public string Exe;
        public string[] Args = new string[0];
        public string WorkingDir;
        public string LogFile;
        public string ErrFile;
        public int Port;
        public string HttpProbe;
        public int ProbeTimeoutMs = 2500;
    }

    // Locates the repository root, loads scripts/server-control/config.json and
    // resolves the <REPO_ROOT> placeholder. Minimal JSON reader; no dependencies.
    internal static class AppConfig
    {
        public static readonly string RepoRoot = FindRepoRoot();
        public static string ConfigPath = Environment.GetEnvironmentVariable("SERVERCTL_CONFIG");

        private static List<ServerConfig> _servers;

        public static List<ServerConfig> Servers
        {
            get
            {
                if (_servers == null) Load();
                return _servers;
            }
        }

        private static string FindRepoRoot()
        {
            try
            {
                var dir = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
                while (dir != null)
                {
                    if (Directory.Exists(Path.Combine(dir.FullName, ".git")))
                        return dir.FullName;
                    dir = dir.Parent;
                }
            }
            catch { }
            return AppDomain.CurrentDomain.BaseDirectory;
        }

        public static string EffectiveConfigPath
        {
            get
            {
                return string.IsNullOrEmpty(ConfigPath)
                    ? Path.Combine(RepoRoot, "scripts", "server-control", "config.json")
                    : ConfigPath;
            }
        }

        private static void Load()
        {
            _servers = Json.ParseServers(File.ReadAllText(EffectiveConfigPath));
        }

        internal static class Json
        {
            public static List<ServerConfig> ParseServers(string text)
            {
                var list = new List<ServerConfig>();
                int i = 0;
                SkipWs(text, ref i);
                Expect(text, ref i, '{');
                while (true)
                {
                    SkipWs(text, ref i);
                    char c = Peek(text, i);
                    if (c == '}') { i++; break; }
                    if (c == '\0') break;
                    string key = ReadString(text, ref i);
                    SkipWs(text, ref i);
                    Expect(text, ref i, ':');
                    SkipWs(text, ref i);
                    if (key == "servers")
                    {
                        Expect(text, ref i, '[');
                        while (true)
                        {
                            SkipWs(text, ref i);
                            if (Peek(text, i) == ']') { i++; break; }
                            list.Add(ParseServer(text, ref i));
                            SkipWs(text, ref i);
                            if (Peek(text, i) == ',') { i++; continue; }
                        }
                    }
                    else
                    {
                        SkipValue(text, ref i);
                    }
                    SkipWs(text, ref i);
                    if (Peek(text, i) == ',') { i++; continue; }
                }
                if (list.Count == 0) throw new Exception("no servers defined in config");
                return list;
            }

            private static ServerConfig ParseServer(string t, ref int i)
            {
                var s = new ServerConfig();
                Expect(t, ref i, '{');
                while (true)
                {
                    SkipWs(t, ref i);
                    if (Peek(t, i) == '}') { i++; break; }
                    string key = ReadString(t, ref i);
                    SkipWs(t, ref i);
                    Expect(t, ref i, ':');
                    SkipWs(t, ref i);
                    switch (key)
                    {
                        case "name": s.Name = ReadString(t, ref i); break;
                        case "description": s.Description = ReadString(t, ref i); break;
                        case "port": s.Port = (int)ReadNumber(t, ref i); break;
                        case "httpProbe": s.HttpProbe = ReadStringOrNull(t, ref i); break;
                        case "probeTimeoutMs": s.ProbeTimeoutMs = (int)ReadNumber(t, ref i); break;
                        case "windows":
                            ParsePlatform(t, ref i, s, true);
                            break;
                        default:
                            SkipValue(t, ref i); // "linux" and unknown keys
                            break;
                    }
                    SkipWs(t, ref i);
                    if (Peek(t, i) == ',') { i++; continue; }
                }
                if (string.IsNullOrEmpty(s.Name)) throw new Exception("server entry without a name");
                return s;
            }

            private static void ParsePlatform(string t, ref int i, ServerConfig s, bool windows)
            {
                Expect(t, ref i, '{');
                while (true)
                {
                    SkipWs(t, ref i);
                    if (Peek(t, i) == '}') { i++; break; }
                    string k = ReadString(t, ref i);
                    SkipWs(t, ref i);
                    Expect(t, ref i, ':');
                    SkipWs(t, ref i);
                    if (k == "exe") s.Exe = Resolve(ReadString(t, ref i));
                    else if (k == "args") s.Args = ReadStringArray(t, ref i).Select(a => Resolve(a)).ToArray();
                    else if (k == "workingDir") s.WorkingDir = Resolve(ReadString(t, ref i));
                    else if (k == "logFile") s.LogFile = Resolve(ReadString(t, ref i));
                    else if (k == "errFile") s.ErrFile = Resolve(ReadString(t, ref i));
                    else SkipValue(t, ref i);
                    SkipWs(t, ref i);
                    if (Peek(t, i) == ',') { i++; continue; }
                }
            }

            private static string Resolve(string p)
            {
                return string.IsNullOrEmpty(p) ? p : p.Replace("<REPO_ROOT>", AppConfig.RepoRoot);
            }

            private static void SkipWs(string t, ref int i) { while (i < t.Length && char.IsWhiteSpace(t[i])) i++; }
            private static char Peek(string t, int i) { return i < t.Length ? t[i] : '\0'; }

            private static void Expect(string t, ref int i, char c)
            {
                if (Peek(t, i) != c)
                    throw new Exception("config parse error at offset " + i + ": expected '" + c + "'");
                i++;
            }

            private static string ReadString(string t, ref int i)
            {
                Expect(t, ref i, '"');
                var sb = new StringBuilder();
                while (i < t.Length)
                {
                    char c = t[i++];
                    if (c == '"') return sb.ToString();
                    if (c == '\\')
                    {
                        char e = t[i++];
                        if (e == 'n') sb.Append('\n');
                        else if (e == 't') sb.Append('\t');
                        else if (e == 'r') sb.Append('\r');
                        else if (e == 'u' && i + 4 <= t.Length)
                        {
                            sb.Append((char)Convert.ToInt32(t.Substring(i, 4), 16));
                            i += 4;
                        }
                        else sb.Append(e);
                    }
                    else sb.Append(c);
                }
                throw new Exception("unterminated string in config");
            }

            private static string ReadStringOrNull(string t, ref int i)
            {
                SkipWs(t, ref i);
                if (Peek(t, i) == 'n') { i += 4; return null; }
                return ReadString(t, ref i);
            }

            private static double ReadNumber(string t, ref int i)
            {
                int start = i;
                while (i < t.Length && "-+.eE0123456789".IndexOf(t[i]) >= 0) i++;
                return double.Parse(t.Substring(start, i - start), System.Globalization.CultureInfo.InvariantCulture);
            }

            private static string[] ReadStringArray(string t, ref int i)
            {
                Expect(t, ref i, '[');
                var items = new List<string>();
                while (true)
                {
                    SkipWs(t, ref i);
                    if (Peek(t, i) == ']') { i++; break; }
                    items.Add(ReadString(t, ref i));
                    SkipWs(t, ref i);
                    if (Peek(t, i) == ',') { i++; continue; }
                }
                return items.ToArray();
            }

            private static void SkipValue(string t, ref int i)
            {
                SkipWs(t, ref i);
                char c = Peek(t, i);
                if (c == '"') { ReadString(t, ref i); return; }
                if (c == '{' || c == '[')
                {
                    char close = c == '{' ? '}' : ']';
                    int depth = 0;
                    while (i < t.Length)
                    {
                        char d = t[i];
                        if (d == '"') { ReadString(t, ref i); continue; }
                        if (d == close && --depth == 0) { i++; return; }
                        if (d == c) depth++;
                        i++;
                    }
                    return;
                }
                if (c == 'n') { i += 4; return; }   // null
                if (c == 't') { i += 4; return; }   // true
                if (c == 'f') { i += 5; return; }   // false
                ReadNumber(t, ref i);
            }
        }
    }

    internal static class ServerControl
    {
        public static string StateDir
        {
            get { return Path.Combine(AppConfig.RepoRoot, ".freebuff", "server-control"); }
        }

        public static ServerConfig Find(string name)
        {
            var s = AppConfig.Servers.FirstOrDefault(x => x.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
            if (s == null)
                throw new Exception("unknown server '" + name + "'. Known: " +
                    string.Join(", ", AppConfig.Servers.Select(x => x.Name)));
            return s;
        }

        public static bool IsPortUp(ServerConfig s)
        {
            try
            {
                using (var c = new TcpClient())
                {
                    IAsyncResult ar = c.BeginConnect("127.0.0.1", s.Port, null, null);
                    if (ar.AsyncWaitHandle.WaitOne(Math.Max(250, s.ProbeTimeoutMs)))
                    {
                        c.EndConnect(ar);
                        return true;
                    }
                    return false;
                }
            }
            catch { return false; }
        }

        public static bool HttpProbe(ServerConfig s)
        {
            if (string.IsNullOrEmpty(s.HttpProbe)) return false;
            try
            {
                var req = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(s.HttpProbe);
                req.Method = "HEAD";
                req.Timeout = Math.Max(250, s.ProbeTimeoutMs);
                req.AllowAutoRedirect = false;
                using (var resp = (System.Net.HttpWebResponse)req.GetResponse())
                    return (int)resp.StatusCode < 500;
            }
            catch { return false; }
        }

        public static string Start(ServerConfig s)
        {
            if (IsPortUp(s)) return s.Name + " already running (port " + s.Port + " up)";
            if (string.IsNullOrEmpty(s.Exe) || !File.Exists(s.Exe))
                throw new Exception("executable not found: " + s.Exe);
            if (!Directory.Exists(s.WorkingDir))
                throw new Exception("working directory not found: " + s.WorkingDir);

            Directory.CreateDirectory(Path.GetDirectoryName(s.LogFile));

            // payload for cmd.exe: "exe" args > log 2> err   (quotes throughout —
            // BuildCmdLine wraps it in the outer " ... " that /s strips)
            string payload = "\"" + s.Exe + "\" " + string.Join(" ", s.Args.Select(Quote)) +
                             " > \"" + s.LogFile + "\" 2> \"" + s.ErrFile + "\"";
            int pid = Detach.Launch(
                Path.Combine(Environment.SystemDirectory, "cmd.exe"),
                payload,
                s.WorkingDir);
            if (pid == 0)
                throw new Exception("failed to launch the server process");

            for (int i = 0; i < 24; i++)   // up to ~6s for the port to come up
            {
                Thread.Sleep(250);
                if (IsPortUp(s))
                {
                    WritePid(s, pid);
                    return s.Name + " started (pid " + pid + ", port " + s.Port + " up)";
                }
            }
            WritePid(s, pid);
            return s.Name + " launched (pid " + pid + ") but port " + s.Port +
                   " is not up yet — check " + s.ErrFile;
        }

        public static string Stop(ServerConfig s)
        {
            if (!IsPortUp(s)) { DeletePid(s); return s.Name + " already stopped (port " + s.Port + " down)"; }

            var killed = new List<int>();
            foreach (int pid in ListenerPids(s.Port))
                KillTree(pid, killed);

            for (int i = 0; i < 16 && IsPortUp(s); i++)
                Thread.Sleep(250);

            DeletePid(s);
            return killed.Count > 0
                ? s.Name + " stopped (killed pid" + (killed.Count > 1 ? "s" : "") + " " +
                  string.Join(", ", killed) + ")"
                : s.Name + ": sent kill but port " + s.Port + " still up";
        }

        public static string Restart(ServerConfig s)
        {
            string stopMsg = Stop(s);
            Thread.Sleep(300);
            return stopMsg + "; " + Start(s);
        }

        public static string StatusLine(ServerConfig s)
        {
            bool up = IsPortUp(s);
            string state = !up ? "STOPPED" : (HttpProbe(s) ? "RUNNING" : "LISTENING");
            string pid = "";
            if (up)
            {
                foreach (int p in ListenerPids(s.Port)) { pid = " pid " + p; break; }
            }
            return state.PadRight(10) + s.Name.PadRight(12) + ("port " + s.Port).PadRight(11) + pid;
        }

        private static IEnumerable<int> ListenerPids(int port)
        {
            var result = new List<int>();
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = Path.Combine(Environment.SystemDirectory, "netstat.exe"),
                    Arguments = "-ano",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true
                };
                using (Process p = Process.Start(psi))
                {
                    string output = p.StandardOutput.ReadToEnd();
                    p.WaitForExit(10000);
                    foreach (string line in output.Split('\n'))
                    {
                        if (line.IndexOf(":" + port + " ", StringComparison.Ordinal) < 0) continue;
                        if (line.IndexOf("LISTEN", StringComparison.OrdinalIgnoreCase) < 0) continue;
                        string[] parts = line.Trim().Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                        int pid;
                        if (parts.Length >= 5 && int.TryParse(parts[parts.Length - 1], out pid))
                            if (pid > 4 && !result.Contains(pid)) result.Add(pid);
                    }
                }
            }
            catch { }
            return result;
        }

        private static void KillTree(int pid, List<int> killed)
        {
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = Path.Combine(Environment.SystemDirectory, "taskkill.exe"),
                    Arguments = "/PID " + pid + " /T /F",
                    UseShellExecute = false,
                    CreateNoWindow = true
                }).WaitForExit(10000);
                killed.Add(pid);
            }
            catch { }
        }

        private static void WritePid(ServerConfig s, int pid)
        {
            try
            {
                Directory.CreateDirectory(StateDir);
                File.WriteAllText(Path.Combine(StateDir, s.Name + ".pid"), pid.ToString());
            }
            catch { }
        }

        private static void DeletePid(ServerConfig s)
        {
            try { File.Delete(Path.Combine(StateDir, s.Name + ".pid")); } catch { }
        }

        private static string Quote(string a)
        {
            return a.IndexOf(' ') >= 0 ? "\"" + a + "\"" : a;
        }
    }

    internal static class Cli
    {
        public static int Run(string[] args)
        {
            var list = new List<string>(args);
            if (list.Count >= 2 && list[0] == "--config")
            {
                AppConfig.ConfigPath = list[1];
                list.RemoveRange(0, 2);
            }

            if (list.Count == 0 || list[0] == "help" || list[0] == "/?")
            {
                Console.WriteLine("usage: ServerCtl.exe <command> [server]");
                Console.WriteLine("  status [name]     show status (all servers if no name given)");
                Console.WriteLine("  start [name]      start a server (detached, survives this console)");
                Console.WriteLine("  stop [name]       stop a server");
                Console.WriteLine("  restart [name]    restart a server");
                Console.WriteLine("  servers           list configured servers");
                Console.WriteLine("  tray              launch ServerTray.exe");
                return 0;
            }

            string cmd = list[0].ToLowerInvariant();

            if (cmd == "servers")
            {
                foreach (ServerConfig s in AppConfig.Servers)
                    Console.WriteLine(s.Name.PadRight(12) + s.Description);
                return 0;
            }

            if (cmd == "tray")
            {
                string dir = AppDomain.CurrentDomain.BaseDirectory;
                string tray = Path.Combine(dir, "ServerTray.exe");
                if (!File.Exists(tray)) throw new Exception("ServerTray.exe not found next to ServerCtl.exe");
                Process.Start(new ProcessStartInfo { FileName = tray, UseShellExecute = true });
                Console.WriteLine("tray app launched");
                return 0;
            }

            string name = list.Count > 1 ? list[1] : AppConfig.Servers[0].Name;
            ServerConfig cfg = ServerControl.Find(name);
            bool ok;

            switch (cmd)
            {
                case "status":
                    Console.WriteLine(ServerControl.StatusLine(cfg));
                    return ServerControl.IsPortUp(cfg) ? 0 : 3;
                case "start":
                    Console.WriteLine(ServerControl.Start(cfg));
                    ok = ServerControl.IsPortUp(cfg);
                    Console.WriteLine(ok ? "status: up" : "status: NOT up");
                    return ok ? 0 : 1;
                case "stop":
                    Console.WriteLine(ServerControl.Stop(cfg));
                    ok = !ServerControl.IsPortUp(cfg);
                    Console.WriteLine(ok ? "status: down" : "status: still up");
                    return ok ? 0 : 1;
                case "restart":
                    Console.WriteLine(ServerControl.Restart(cfg));
                    ok = ServerControl.IsPortUp(cfg);
                    Console.WriteLine(ok ? "status: up" : "status: NOT up");
                    return ok ? 0 : 1;
                default:
                    throw new Exception("unknown command '" + cmd + "' (try help)");
            }
        }
    }

    internal sealed class TrayApp : ApplicationContext
    {
        private NotifyIcon _icon;
        private Control _marshal;                       // UI-thread marshal helper
        private ContextMenuStrip _menu;
        private readonly Dictionary<string, List<ToolStripMenuItem>> _items =
            new Dictionary<string, List<ToolStripMenuItem>>();
        private ToolStripMenuItem _autostartItem;
        private static readonly Icon[] Icons = new Icon[3]; // 0=stopped 1=partial 2=running

        public static int Run()
        {
            bool createdNew;
            using (Mutex single = new Mutex(true, "PwEeveeServerTray", out createdNew))
            {
                if (!createdNew)
                {
                    MessageBox.Show("ServerTray is already running in the notification area.",
                        "ServerTray", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return 0;
                }
                Application.EnableVisualStyles();
                Application.Run(new TrayApp());
            }
            return 0;
        }

        private TrayApp()
        {
            _marshal = new Control();
            _marshal.CreateControl();
            IntPtr forceHandle = _marshal.Handle;   // force handle creation for BeginInvoke

            _icon = new NotifyIcon
            {
                Icon = IconFor(0),
                Text = "ServerTray — starting",
                Visible = true
            };
            _icon.DoubleClick += delegate { ShowStatus(); };

            BuildMenu();
            UpdateIcon();
        }

        private void BuildMenu()
        {
            _menu = new ContextMenuStrip();
            bool single = AppConfig.Servers.Count == 1;

            foreach (ServerConfig s in AppConfig.Servers)
            {
                string label = single ? "Server" : " " + s.Name;
                var entries = new List<ToolStripMenuItem>
                {
                    Add("🟢 Start" + label, delegate { DoAction(s, "start"); }),
                    Add("🔴 Stop" + label, delegate { DoAction(s, "stop"); }),
                    Add("🔄 Restart" + label, delegate { DoAction(s, "restart"); })
                };
                _items[s.Name] = entries;
                if (!single) _menu.Items.Add(new ToolStripSeparator());
            }

            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(Add("📊 Server Status", delegate { ShowStatus(); }));
            _menu.Items.Add(Add("⚙ Run at startup", delegate { ToggleAutostart(); }));
            _autostartItem = (ToolStripMenuItem)_menu.Items[_menu.Items.Count - 1];
            _autostartItem.CheckOnClick = true;
            _autostartItem.Checked = AutostartEnabled();
            _menu.Items.Add(Add("⚙ Settings", delegate { OpenSettings(); }));

            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(Add("❌ Exit", delegate
            {
                _icon.Visible = false;
                Application.Exit();
            }));

            _menu.Opening += delegate { RefreshMenu(); };
            _icon.ContextMenuStrip = _menu;
        }

        private ToolStripMenuItem Add(string text, EventHandler onClick)
        {
            var item = new ToolStripMenuItem(text);
            item.Click += onClick;
            _menu.Items.Add(item);
            return item;
        }

        private void DoAction(ServerConfig s, string action)
        {
            Balloon("Server " + action, s.Name + ": working...");
            ThreadPool.QueueUserWorkItem(delegate
            {
                string msg;
                try
                {
                    switch (action)
                    {
                        case "start": msg = ServerControl.Start(s); break;
                        case "stop": msg = ServerControl.Stop(s); break;
                        default: msg = ServerControl.Restart(s); break;
                    }
                }
                catch (Exception ex)
                {
                    msg = "error: " + ex.Message;
                }
                _marshal.BeginInvoke((MethodInvoker)delegate
                {
                    Balloon("Server " + action, msg);
                    UpdateIcon();
                    RefreshMenu();
                });
            });
        }

        private void Balloon(string title, string text)
        {
            try { _icon.ShowBalloonTip(1500, title, text, ToolTipIcon.Info); } catch { }
        }

        private void UpdateIcon()
        {
            int up = AppConfig.Servers.Count(x => ServerControl.IsPortUp(x));
            int state = up == 0 ? 0 : (up == AppConfig.Servers.Count ? 2 : 1);
            _icon.Icon = IconFor(state);
            ServerConfig first = AppConfig.Servers[0];
            _icon.Text = "ServerTray — " + first.Name +
                (up == 0 ? " stopped" : " running (port " + first.Port + ")");
        }

        private void RefreshMenu()
        {
            foreach (ServerConfig s in AppConfig.Servers)
            {
                bool up = ServerControl.IsPortUp(s);
                List<ToolStripMenuItem> e = _items[s.Name];
                e[0].Enabled = !up;   // start
                e[1].Enabled = up;    // stop
                e[2].Enabled = true;  // restart
                e[2].Text = "🔄 Restart" + (AppConfig.Servers.Count == 1 ? " Server" : " " + s.Name) +
                            (up ? "  (running)" : "  (stopped)");
            }
            UpdateIcon();
        }

        private void ShowStatus()
        {
            var sb = new StringBuilder();
            foreach (ServerConfig s in AppConfig.Servers)
            {
                sb.AppendLine(ServerControl.StatusLine(s));
                sb.AppendLine("           " + s.Description);
            }
            sb.AppendLine();
            sb.Append("config: " + AppConfig.EffectiveConfigPath);
            MessageBox.Show(sb.ToString(), "Server status", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void OpenSettings()
        {
            try { Process.Start("notepad.exe", "\"" + AppConfig.EffectiveConfigPath + "\""); }
            catch
            {
                MessageBox.Show(AppConfig.EffectiveConfigPath, "Settings file",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private static string AutostartKey
        {
            get { return "Software\\Microsoft\\Windows\\CurrentVersion\\Run"; }
        }
        private const string AutostartValue = "PwEeveeServerTray";

        private static bool AutostartEnabled()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(AutostartKey))
                    return k != null && k.GetValue(AutostartValue) != null;
            }
            catch { return false; }
        }

        private void ToggleAutostart()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(AutostartKey))
                {
                    if (_autostartItem.Checked)
                        k.SetValue(AutostartValue, "\"" + Application.ExecutablePath + "\"");
                    else
                        k.DeleteValue(AutostartValue, false);
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "Run at startup", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private static Icon IconFor(int state)
        {
            if (Icons[state] == null)
            {
                Color c = state == 2 ? Color.FromArgb(46, 204, 113)      // green
                        : state == 1 ? Color.FromArgb(241, 196, 15)      // yellow
                        : Color.FromArgb(231, 76, 60);                   // red
                using (var bmp = new Bitmap(16, 16))
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                    using (SolidBrush b = new SolidBrush(c)) g.FillEllipse(b, 2, 2, 12, 12);
                    using (Pen p = new Pen(Color.FromArgb(70, 0, 0, 0))) g.DrawEllipse(p, 2, 2, 12, 12);
                    Icons[state] = Icon.FromHandle(bmp.GetHicon());
                }
            }
            return Icons[state];
        }
    }
}
