@echo off
rem Build ServerTray.exe (tray app) and ServerCtl.exe (console CLI) with the
rem in-box .NET Framework compiler. No SDK, no installs. Run from anywhere.
setlocal
set "HERE=%~dp0"
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
    echo error: csc.exe not found - install .NET Framework 4.x or use a newer Windows.
    exit /b 1
)

set "REFS=/r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Net.Http.dll /r:System.Net.Http.WebRequest.dll /r:System.Management.dll"
set "SRC=%HERE%ServerTray.cs"

rem /target:winexe = no console window ever (tray). /target:exe = console CLI.
"%CSC%" /nologo /target:winexe /platform:anycpu /out:"%HERE%ServerTray.exe" %REFS% "%SRC%" || exit /b 1
"%CSC%" /nologo /target:exe    /platform:anycpu /out:"%HERE%ServerCtl.exe"    %REFS% "%SRC%" || exit /b 1

echo built:
for %%F in ("%HERE%ServerTray.exe" "%HERE%ServerCtl.exe") do echo   %%F
exit /b 0
