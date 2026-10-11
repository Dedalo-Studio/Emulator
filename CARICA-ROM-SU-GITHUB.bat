@echo off
chcp 65001 >nul
title Dedalo Game - Sincronizzazione ROM su GitHub

echo ============================================================
echo      🎮 DEDALO GAME - SINCRONIZZAZIONE ROM SU GITHUB
echo ============================================================
echo.

set "GIT_CMD=git"
where git >nul 2>nul
if %errorlevel% neq 0 (
    if exist "C:\Program Files\Git\bin\git.exe" set "GIT_CMD=C:\Program Files\Git\bin\git.exe"
    if exist "C:\Users\%USERNAME%\AppData\Local\Programs\Git\bin\git.exe" set "GIT_CMD=C:\Users\%USERNAME%\AppData\Local\Programs\Git\bin\git.exe"
)

echo [1/3] Controllo nuovi file nella cartella roms...
"%GIT_CMD%" add roms/* >nul 2>nul

echo [2/3] Preparazione aggiornamento...
"%GIT_CMD%" commit -m "Aggiornamento ROM e copertine personali" >nul 2>nul

echo [3/3] Invio a GitHub in corso...
"%GIT_CMD%" push origin main

if %errorlevel% equ 0 (
    echo.
    echo ============================================================
    echo  ✨ OPERAZIONE COMPLETATA CON SUCCESSO!
    echo.
    echo  Le tue ROM sono ora online su GitHub Pages!
    echo  Puoi usare i tuoi Tag NFC da qualsiasi telefono,
    echo  anche a computer completamente SPENTO.
    echo ============================================================
) else (
    echo.
    echo [!] Nessun nuovo file da caricare oppure errore di connessione.
)

echo.
pause
