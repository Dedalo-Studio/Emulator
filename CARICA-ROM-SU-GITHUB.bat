@echo off
setlocal
cd /d "%~dp0"
echo Connessione a Dropbox e sincronizzazione catalogo in corso...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync-dropbox.ps1"
echo.
pause
