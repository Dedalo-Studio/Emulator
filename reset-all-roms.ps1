# ============================================================
#  DEDALO GAME - Cancellazione Totale ROM & Reset Database
# ============================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Red
Write-Host "      ATTENZIONE: CANCELLAZIONE TOTALE DELLE ROM E DEL DATABASE       " -ForegroundColor Red
Write-Host "======================================================================" -ForegroundColor Red
Write-Host ""
Write-Host "Questa operazione:" -ForegroundColor Yellow
Write-Host " 1. Eliminera' TUTTE le ROM e le copertine dalla cartella 'roms' del PC" -ForegroundColor White
Write-Host " 2. Eliminera' TUTTI i giochi dal database online" -ForegroundColor White
Write-Host " 3. Rimuovera' tutti i file da GitHub (sincronizzazione immediata)" -ForegroundColor White
Write-Host ""

$conferma = Read-Host "Sei SICURO di voler cancellare TUTTO? (scrivi S per confermare)"
if ($conferma -notmatch '^[sSyY]$') {
    Write-Host ""
    Write-Host "Operazione ANNULLATA. Nessun file e' stato eliminato." -ForegroundColor Green
    Write-Host ""
    return
}

Write-Host ""
Write-Host "[1/3] Eliminazione file locali in corso..." -ForegroundColor Yellow

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$romsDir = Join-Path $scriptDir "roms"
if (Test-Path -LiteralPath $romsDir) {
    $files = Get-ChildItem -LiteralPath $romsDir -File
    $count = $files.Count
    $files | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "  -> Rimossi $count file dalla cartella 'roms' (giochi, cover e mapping)." -ForegroundColor Cyan
}

$oldRomDir = Join-Path $scriptDir "rom"
if (Test-Path -LiteralPath $oldRomDir) {
    Remove-Item -LiteralPath $oldRomDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Ripristina database.json vuoto e pulito
Write-Host "[2/3] Azzeramento del database online..." -ForegroundColor Yellow
$emptyDb = [ordered]@{
    app       = "dedalo-nfc"
    version   = "1.0"
    updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    tags      = @()
}
$databasePath = Join-Path $scriptDir "database.json"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($databasePath, ($emptyDb | ConvertTo-Json -Depth 4), $utf8NoBom)

# Aggiorna il file I-MIEI-GIOCHI.txt
$summaryPath = Join-Path $scriptDir "I-MIEI-GIOCHI.txt"
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("======================================================================")
[void]$sb.AppendLine("  DEDALO GAME - NESSUN GIOCO CARICATO (DATABASE AZZERATO)")
[void]$sb.AppendLine("======================================================================")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Tutte le ROM precedenti sono state cancellate.")
[void]$sb.AppendLine("Per caricare nuovi giochi, inseriscili nella cartella 'roms' e avvia CARICA-ROM-SU-GITHUB.bat.")
Set-Content -LiteralPath $summaryPath -Value ($sb.ToString()) -Encoding UTF8

Write-Host "  -> database.json e I-MIEI-GIOCHI.txt azzerati con successo." -ForegroundColor Cyan

# Git commit e push su GitHub
Write-Host "[3/3] Sincronizzazione ed eliminazione su GitHub..." -ForegroundColor Yellow

$gitCmd = "git"
$gitFound = $false
try {
    $null = Get-Command git -ErrorAction Stop
    $gitFound = $true
} catch {
    $candidates = @(
        "C:\Program Files\Git\bin\git.exe",
        "C:\Program Files (x86)\Git\bin\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\git.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $gitCmd = $c
            $gitFound = $true
            break
        }
    }
}

if (-not $gitFound) {
    Write-Host ""
    Write-Host "ERRORE: Git non trovato sul sistema!" -ForegroundColor Red
    return
}

& $gitCmd add -A
& $gitCmd commit -m "Eliminazione totale di tutte le ROM e reset database" 2>&1 | Out-Null
$pushOutput = & $gitCmd push origin main 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "  TUTTO CANCELLATO CON SUCCESSO SIA DAL PC CHE DA GITHUB!" -ForegroundColor Green
    Write-Host "  Il database e' ora vuoto e pulito al 100%." -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "ERRORE DURANTE IL PUSH SU GITHUB:" -ForegroundColor Red
    Write-Host $pushOutput -ForegroundColor Red
}
Write-Host ""
