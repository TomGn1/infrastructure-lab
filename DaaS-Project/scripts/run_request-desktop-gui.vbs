' C:\Scripts\Launch-DaaS-GUI.vbs
Set objShell = CreateObject("Wscript.Shell")
objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\Scripts\Request-Desktop-GUI.ps1""", 1, True