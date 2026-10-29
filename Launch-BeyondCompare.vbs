Set oShell = CreateObject("WScript.Shell")
On Error Resume Next
' Auto-reset trial keys
oShell.RegDelete "HKCU\Software\Scooter Software\Beyond Compare 5\Expired"
oShell.RegDelete "HKCU\Software\Scooter Software\Beyond Compare 5\CacheID"
oShell.RegDelete "HKCU\Software\Scooter Software\Beyond Compare 4\Expired"
oShell.RegDelete "HKCU\Software\Scooter Software\Beyond Compare 4\CacheID"

sExe = "C:\Program Files\Beyond Compare 5\BCompare.exe"
Set oFSO = CreateObject("Scripting.FileSystemObject")
If Not oFSO.FileExists(sExe) Then
    sExe = oFSO.GetParentFolderName(WScript.ScriptFullName) & "\Beyond Compare 5\BCompare.exe"
End If
If Not oFSO.FileExists(sExe) Then
    sExe = "C:\Program Files (x86)\Beyond Compare 5\BCompare.exe"
End If

If oFSO.FileExists(sExe) Then
    oShell.Run """" & sExe & """", 1, False
Else
    sCmd = oFSO.GetParentFolderName(WScript.ScriptFullName) & "\Beyond-Compare-5.cmd"
    oShell.Run """" & sCmd & """", 0, False
End If
