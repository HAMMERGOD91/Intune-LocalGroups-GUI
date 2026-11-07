@echo off
where pwsh.exe >nul 2>&1
if errorlevel 1 goto WindowsPowerShell
pwsh.exe -NoProfile -STA -File "%~dp0Intune-LocalGroups-GUI.ps1"
goto Finished
:WindowsPowerShell
powershell.exe -NoProfile -STA -File "%~dp0Intune-LocalGroups-GUI.ps1"
:Finished
if errorlevel 1 pause
