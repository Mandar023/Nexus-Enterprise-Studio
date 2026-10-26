On Error Resume Next
Set FSO = CreateObject("Scripting.FileSystemObject")
ScriptDir = FSO.GetParentFolderName(WScript.ScriptFullName)
Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = ScriptDir

' 1. Silently unblock all script files to prevent SmartScreen / ExecutionPolicy blocks
WshShell.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -Command ""Get-ChildItem -Path '" & ScriptDir & "' -Recurse | Unblock-File -ErrorAction SilentlyContinue""", 0, True

' 2. Try running via elevated Scheduled Task if registered (Full Admin with ZERO UAC Prompts)
RetVal = WshShell.Run("schtasks /run /tn ""NexusPhotoOptimizerAdmin""", 0, True)
If RetVal = 0 Then
    WScript.Quit
End If

' 3. Try running elevated directly as Administrator via ShellExecute runas
Set objShell = CreateObject("Shell.Application")
Err.Clear
objShell.ShellExecute "powershell.exe", "-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File """ & ScriptDir & "\PMC-ImageResizer-App.ps1""", "", "runas", 0

' 4. Fallback: If elevation was cancelled or unavailable, run directly so user is never blocked
If Err.Number <> 0 Then
    WshShell.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File """ & ScriptDir & "\PMC-ImageResizer-App.ps1""", 0, False
End If
