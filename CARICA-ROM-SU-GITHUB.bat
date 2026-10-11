@echo off
chcp 65001 >nul
title Dedalo Game - Sincronizzazione ROM e Randomizzazione

echo ============================================================
echo      🎮 DEDALO GAME - RANDOMIZZATORE & SYNC SU GITHUB
echo ============================================================
echo.

set "GIT_CMD=git"
where git >nul 2>nul
if %errorlevel% neq 0 (
    if exist "C:\Program Files\Git\bin\git.exe" set "GIT_CMD=C:\Program Files\Git\bin\git.exe"
    if exist "C:\Users\%USERNAME%\AppData\Local\Programs\Git\bin\git.exe" set "GIT_CMD=C:\Users\%USERNAME%\AppData\Local\Programs\Git\bin\git.exe"
)

echo [1/3] Assegnazione nomi casuali segreti alle ROM e immagini...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync-roms.ps1"

echo.
echo [2/3] Preparazione aggiornamento su GitHub...
"%GIT_CMD%" add roms/* database.json I-MIEI-GIOCHI.txt >nul 2>nul
"%GIT_CMD%" commit -m "Sincronizzazione giochi con codici casuali protetti" >nul 2>nul

echo [3/3] Invio a GitHub Pages...
"%GIT_CMD%" push origin main

if %errorlevel% equ 0 (
    echo.
    echo ============================================================
    echo  ✨ SINCRONIZZAZIONE COMPLETATA AL 100%!
    echo.
    echo  Tutti i file sono stati protetti con codici CASUALI
    echo  impossibili da indovinare da chiunque!
    echo.
    echo  I giochi sono gia' presenti nella sezione 'I Miei Tag'
    echo  dello Studio sul tuo telefono:
    echo  https://rivegabry.github.io/emulatore-nfc/
    echo.
    echo  Puoi anche consultare il file "I-MIEI-GIOCHI.txt"!
    echo ============================================================
) else (
    echo.
    echo [!] Nessun nuovo file da caricare oppure errore di connessione.
)

echo.
pause
