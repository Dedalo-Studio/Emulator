# ============================================================
#  DEDALO GAME - Sincronizzatore Automatico & Randomizzatore ROM
# ============================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "         DEDALO GAME - SINCRONIZZATORE ROM & COPERTINE                " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$romsDir = Join-Path $scriptDir "roms"
if (-not (Test-Path -LiteralPath $romsDir)) {
    New-Item -ItemType Directory -Path $romsDir | Out-Null
}

# 1. Carica mapping esistente
$mappingFile = Join-Path $romsDir "mapping.json"
$mapping = [ordered]@{}
if (Test-Path -LiteralPath $mappingFile) {
    try {
        $jsonContent = Get-Content -LiteralPath $mappingFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $jsonContent.PSObject.Properties) {
            $mapping[$prop.Name] = $prop.Value
        }
    } catch {
        Write-Warning "Impossibile leggere mapping.json precedente: $_"
    }
}

# 1a. Migrazione automatica dai vecchi nomi r_ / cov_ al nuovo formato: '[Nome Originale] [codice]'
$migrationCount = 0
foreach ($k in @($mapping.Keys)) {
    $item = $mapping[$k]
    if ($item.randomRom -and $item.randomRom.StartsWith("r_")) {
        $token = $k.Replace("g_", "")
        $oldRom = Join-Path $romsDir $item.randomRom
        $ext = [System.IO.Path]::GetExtension($item.randomRom)
        $cleanBase = $item.originalName.Trim()
        $newBase = "$cleanBase $token"
        $newRomName = "$newBase$ext"

        if (Test-Path -LiteralPath $oldRom) {
            Rename-Item -LiteralPath $oldRom -NewName $newRomName
            $item.randomRom = $newRomName
            $migrationCount++
        }

        if ($item.randomCover -and $item.randomCover.StartsWith("cov_")) {
            $oldCover = Join-Path $romsDir $item.randomCover
            $covExt = [System.IO.Path]::GetExtension($item.randomCover)
            $newCoverName = "$newBase$covExt"
            if (Test-Path -LiteralPath $oldCover) {
                Rename-Item -LiteralPath $oldCover -NewName $newCoverName
                $item.randomCover = $newCoverName
            }
        }
    }
}
if ($migrationCount -gt 0) {
    Write-Host "  [+] Migrati $migrationCount file al nuovo formato '[Nome] [Codice]'." -ForegroundColor Cyan
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($mappingFile, ($mapping | ConvertTo-Json -Depth 5), $utf8NoBom)
}

# 1b. Rileva e rimuovi dal catalogo le ROM eliminate dal disco
$deletedKeys = @()
foreach ($k in $mapping.Keys) {
    $romFile = Join-Path $romsDir $mapping[$k].randomRom
    if (-not (Test-Path -LiteralPath $romFile)) {
        Write-Host "  [-] Rilevata eliminazione: '$($mapping[$k].originalName)' (ROM non piu' sul disco)" -ForegroundColor Yellow
        if ($mapping[$k].randomCover) {
            $orphanCover = Join-Path $romsDir $mapping[$k].randomCover
            if (Test-Path -LiteralPath $orphanCover) {
                Remove-Item -LiteralPath $orphanCover -Force -ErrorAction SilentlyContinue
                Write-Host "      -> Rimossa copertina orfana: $($mapping[$k].randomCover)" -ForegroundColor DarkGray
            }
        }
        $deletedKeys += $k
    }
}
if ($deletedKeys.Count -gt 0) {
    foreach ($k in $deletedKeys) {
        $mapping.Remove($k)
    }
    Write-Host "  -> Rimossi $($deletedKeys.Count) giochi obsoleti dal catalogo." -ForegroundColor Yellow
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($mappingFile, ($mapping | ConvertTo-Json -Depth 5), $utf8NoBom)
}

$supportedExts = @('.gba', '.gbc', '.gb', '.nes', '.snes', '.smc', '.sfc', '.n64', '.z64', '.v64', '.nds', '.md', '.gen', '.smd', '.sms', '.gg', '.a26', '.zip')
$imageExts     = @('.png', '.jpg', '.jpeg', '.webp')

function Get-CoreByExt($ext) {
    switch ($ext.ToLower()) {
        '.gba'  { return 'gba' }
        '.gbc'  { return 'gb' }
        '.gb'   { return 'gb' }
        '.nes'  { return 'nes' }
        '.snes' { return 'snes' }
        '.smc'  { return 'snes' }
        '.sfc'  { return 'snes' }
        '.n64'  { return 'n64' }
        '.z64'  { return 'n64' }
        '.v64'  { return 'n64' }
        '.nds'  { return 'nds' }
        '.md'   { return 'segaMD' }
        '.gen'  { return 'segaMD' }
        '.smd'  { return 'segaMD' }
        '.sms'  { return 'segaMS' }
        '.gg'   { return 'segaGG' }
        '.a26'  { return 'atari2600' }
        default { return 'gba' }
    }
}

# 2. Trova nuove ROM non ancora registrate
$knownRomFiles = @($mapping.Values | ForEach-Object { if ($_.randomRom) { $_.randomRom.ToLower() } })
$romFiles = Get-ChildItem -LiteralPath $romsDir -File | Where-Object {
    $ext = $_.Extension.ToLower()
    $name = $_.Name.ToLower()
    ($supportedExts -contains $ext) -and (-not ($knownRomFiles -contains $name))
}

$newProcessed = @()

if ($romFiles.Count -gt 0) {
    Write-Host "[1/3] Rilevati $($romFiles.Count) nuovi file da elaborare nella cartella roms:" -ForegroundColor Yellow
    foreach ($rf in $romFiles) {
        Write-Host "   -> $($rf.Name)" -ForegroundColor Gray
    }
    Write-Host ""

    foreach ($file in $romFiles) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $cleanTitle = $baseName.Replace('_', ' ').Trim()
        $ext = $file.Extension.ToLower()

        # Estrai token esistente se gia' presente, oppure generane uno casuale di 10 caratteri
        $token = ""
        if ($cleanTitle -match '^(.+?)\s+([a-f0-9]{9,12})$') {
            $cleanTitle = $matches[1].Trim()
            $token = $matches[2]
        } else {
            $token = [System.Guid]::NewGuid().ToString('N').Substring(0, 10)
        }

        # Stesso nome esatto per gioco e foto: "[Nome] [Codice]"
        $unifiedBaseName = "$cleanTitle $token"
        $newRomName = "$unifiedBaseName$ext"

        # Cerca eventuale immagine di copertina associata (stesso nome originale prima del codice)
        $newImgName = ""
        foreach ($imgExt in $imageExts) {
            $candidateImg = Join-Path $romsDir "$baseName$imgExt"
            if (-not (Test-Path -LiteralPath $candidateImg)) {
                $candidateImg = Join-Path $romsDir "$cleanTitle$imgExt"
            }
            if (Test-Path -LiteralPath $candidateImg) {
                $newImgName = "$unifiedBaseName$imgExt"
                Rename-Item -LiteralPath $candidateImg -NewName $newImgName
                break
            }
        }

        # Rinomina la ROM mantenendo il nome e aggiungendo il codice
        if ($file.Name -ne $newRomName) {
            Rename-Item -LiteralPath $file.FullName -NewName $newRomName
        }

        $core = Get-CoreByExt $ext
        $tagId = "g_$token"
        $finalLink = "https://rivegabry.github.io/emulatore-nfc/?tag=$tagId"
        $dateStr = (Get-Date).ToString("dd/MM/yyyy")

        $mapping[$tagId] = [ordered]@{
            originalName = $cleanTitle
            randomRom    = $newRomName
            randomCover  = $newImgName
            core         = $core
            link         = $finalLink
            date         = $dateStr
        }

        $newProcessed += $cleanTitle

        Write-Host "  [OK] ELABORATO: $cleanTitle" -ForegroundColor Green
        Write-Host "       Console:        $($core.ToUpper())" -ForegroundColor Gray
        Write-Host "       File ROM:       roms/$newRomName" -ForegroundColor Gray
        if ($newImgName) {
            Write-Host "       Copertina:      roms/$newImgName (stesso nome del gioco!)" -ForegroundColor Gray
        } else {
            Write-Host "       Copertina:      (nessuna foto trovata con lo stesso nome)" -ForegroundColor DarkGray
        }
        Write-Host "       Link Tag NFC:   $finalLink" -ForegroundColor Gray
        Write-Host ""
    }

    # Salva mapping aggiornato
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($mappingFile, ($mapping | ConvertTo-Json -Depth 5), $utf8NoBom)

} else {
    Write-Host "[1/3] Nessun nuovo file ROM trovato da elaborare." -ForegroundColor DarkGray
    Write-Host "      (Tutte le ROM presenti sono gia' sincronizzate con il loro codice)" -ForegroundColor DarkGray
    Write-Host ""
}

# 3. Aggiorna database.json nel repository per GitHub Pages
Write-Host "[2/3] Aggiornamento database.json per GitHub Pages..." -ForegroundColor Cyan
$dbTags = @()
foreach ($k in $mapping.Keys) {
    $item = $mapping[$k]
    $coverUrl = ""
    if ($item.randomCover) {
        $encodedCover = [System.Uri]::EscapeUriString($item.randomCover)
        $coverUrl = "https://rivegabry.github.io/emulatore-nfc/roms/$encodedCover"
    }
    $encodedRom = [System.Uri]::EscapeUriString($item.randomRom)
    $romUrl = "https://rivegabry.github.io/emulatore-nfc/roms/$encodedRom"
    $linkUrl = $item.link
    $qrPrefix = 'https://api.qrserver.com/v1/create-qr-code/?size=220x220&margin=4&data='
    $qrUrl = $qrPrefix + [System.Uri]::EscapeDataString($linkUrl)

    $dbTags += [ordered]@{
        id         = $k
        name       = $item.originalName
        core       = $item.core
        rom        = $romUrl
        cover      = $coverUrl
        shader     = "crt-easymode.glslp"
        link       = $linkUrl
        directLink = $linkUrl
        qr         = $qrUrl
        date       = $item.date
    }
}

$dbObj = [ordered]@{
    app       = "dedalo-nfc"
    version   = "1.0"
    updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    tags      = $dbTags
}

$databasePath = Join-Path $scriptDir "database.json"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($databasePath, ($dbObj | ConvertTo-Json -Depth 6), $utf8NoBom)

# Rigenera il file riassuntivo per Gabry I-MIEI-GIOCHI.txt
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("======================================================================")
[void]$sb.AppendLine("  DEDALO GAME - I TUOI GIOCHI SINCRONIZZATI E RANDOMIZZATI")
[void]$sb.AppendLine("  Questi link sono protetti: nessuno puo' indovinare le altre ROM!")
[void]$sb.AppendLine("======================================================================")
[void]$sb.AppendLine("")

foreach ($k in $mapping.Keys) {
    $item = $mapping[$k]
    [void]$sb.AppendLine("----------------------------------------------------------------------")
    [void]$sb.AppendLine("GIOCO:          $($item.originalName) [$($item.core.ToUpper())]")
    [void]$sb.AppendLine("Link NFC Chip:  $($item.link)")
    [void]$sb.AppendLine("File ROM Cloud: roms/$($item.randomRom)")
    if ($item.randomCover) {
        [void]$sb.AppendLine("Copertina:      roms/$($item.randomCover)")
    }
    [void]$sb.AppendLine("Data:           $($item.date)")
    [void]$sb.AppendLine("----------------------------------------------------------------------")
    [void]$sb.AppendLine("")
}

$summaryPath = Join-Path $scriptDir "I-MIEI-GIOCHI.txt"
Set-Content -LiteralPath $summaryPath -Value ($sb.ToString()) -Encoding UTF8

# 4. Git commit & push su GitHub Pages
Write-Host "[3/3] Invio a GitHub Pages in corso..." -ForegroundColor Cyan

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
    Write-Host "ERRORE: Git non e' stato trovato sul computer!" -ForegroundColor Red
    Write-Host "Assicurati che Git sia installato per inviare i file su GitHub." -ForegroundColor Red
    return
}

# Controllo modifiche git
$status = & $gitCmd status --porcelain 2>&1
if ([string]::IsNullOrWhiteSpace($status)) {
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "  TUTTO GIA' AGGIORNATO!" -ForegroundColor Green
    Write-Host "  Tutti i tuoi $($mapping.Count) giochi sono gia' sincronizzati su GitHub!" -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
} else {
    & $gitCmd add -A
    $msg = "Aggiornamento catalogo giochi: " + ($newProcessed -join ", ")
    if ($newProcessed.Count -eq 0) { $msg = "Aggiornamento sincronizzazione giochi" }
    & $gitCmd commit -m $msg 2>&1 | Out-Null
    
    $pushOutput = & $gitCmd push origin main 2>&1
    $pushSuccess = $LASTEXITCODE -eq 0

    if ($pushSuccess) {
        Write-Host ""
        Write-Host "======================================================================" -ForegroundColor Green
        Write-Host "  OPERAZIONE COMPLETATA CON SUCCESSO!" -ForegroundColor Green
        Write-Host "  I seguenti giochi sono stati caricati e sono ONLINE:" -ForegroundColor Green
        foreach ($k in $mapping.Keys) {
            $g = $mapping[$k]
            Write-Host "   - $($g.originalName) [$($g.core.ToUpper())]" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "  I tuoi giochi sono pronti nella sezione I Miei Tag:" -ForegroundColor Yellow
        Write-Host "  https://rivegabry.github.io/emulatore-nfc/" -ForegroundColor Cyan
        Write-Host "======================================================================" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "ERRORE DURANTE L'INVIO A GITHUB:" -ForegroundColor Red
        Write-Host $pushOutput -ForegroundColor Red
        Write-Host "Controlla la connessione internet e riprova." -ForegroundColor Red
    }
}
Write-Host ""
