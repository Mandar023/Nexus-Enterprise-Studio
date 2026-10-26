On Error Resume Next
Set FSO = CreateObject("Scripting.FileSystemObject")
ScriptDir = FSO.GetParentFolderName(WScript.ScriptFullName)
Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = ScriptDir

' 1. Silently unblock all files to eliminate SmartScreen / ExecutionPolicy blocks
WshShell.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -Command ""Get-ChildItem -Path '" & ScriptDir & "' -Recurse | Unblock-File -ErrorAction SilentlyContinue""", 0, True

' 2. Try running via elevated Scheduled Task if registered (Full Admin with ZERO UAC Prompts)
RetVal = WshShell.Run("schtasks /run /tn ""NexusPhotoOptimizerAdmin""", 0, True)
If RetVal = 0 Then
    WScript.Quit
End If

' 3. Check if current user is an Administrator (has S-1-5-32-544 in groups)
IsAdminUser = False
RetVal = WshShell.Run("cmd.exe /c ""whoami /groups | findstr /i S-1-5-32-544 >nul""", 0, True)
If RetVal = 0 Then
    IsAdminUser = True
End If

' 4. If user is in Administrators group, elevate seamlessly via runas
If IsAdminUser Then
    Set objShell = CreateObject("Shell.Application")
    Err.Clear
    objShell.ShellExecute "powershell.exe", "-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File """ & ScriptDir & "\PMC-ImageResizer-App.ps1""", "", "runas", 0
    If Err.Number = 0 Then
        WScript.Quit
    End If
End If

' 5. Direct launch: If standard user, or elevation declined/unavailable, launch directly without blocking or asking for permission
WshShell.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File """ & ScriptDir & "\PMC-ImageResizer-App.ps1""", 0, False
