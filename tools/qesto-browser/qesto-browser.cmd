@echo off
set SCRIPT=%~dp0qesto-browser.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
