Option Explicit
Dim shell, fs, root, runtime, command
Set shell = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
root = fs.GetParentFolderName(WScript.ScriptFullName)
runtime = fs.BuildPath(root, "co-op\runtime")
shell.CurrentDirectory = runtime
command = Chr(34) & fs.BuildPath(runtime, "projectpitt.exe") & Chr(34) & " --log-file " & Chr(34) & "../logs/play.log" & Chr(34) & " --windowed --resolution 1280x960"
shell.Run command, 1, False
