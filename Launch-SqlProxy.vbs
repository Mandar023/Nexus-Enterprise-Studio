Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = scriptDir & "\PMC-SqlProxy-Service.ps1"

If Not fso.FileExists(psScript) Then
    MsgBox "PMC-SqlProxy-Service.ps1 not found in:" & vbCrLf & scriptDir, vbCritical, "PMC SQL Proxy"
    WScript.Quit
End If

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & psScript & """"
WshShell.Run cmd, 1, False
