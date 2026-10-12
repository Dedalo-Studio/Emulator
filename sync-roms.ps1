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

# 2. Trova nuove ROM non ancora randomizzate (non iniziano con r_)
$romFiles = Get-ChildItem -LiteralPath $romsDir -File | Where-Object {
    $ext = $_.Extension.ToLower()
    $name = $_.Name.ToLower()
    ($supportedExts -contains $ext) -and (-not $name.StartsWith("r_"))
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

        # Genera token crittografico casuale di 12 caratteri
        $token = [System.Guid]::NewGuid().ToString('N').Substring(0, 12)
        $randomRomName = "r_$token$ext"

        # Cerca eventuale immagine di copertina associata (stesso nome file)
        $randomImgName = ""
        foreach ($imgExt in $imageExts) {
            $candidateImg = Join-Path $romsDir "$baseName$imgExt"
            if (Test-Path -LiteralPath $candidateImg) {
                $randomImgName = "cov_$token$imgExt"
                Rename-Item -LiteralPath $candidateImg -NewName $randomImgName
                break
            }
        }

        # Rinomina la ROM con il nome casuale protetto
        Rename-Item -LiteralPath $file.FullName -NewName $randomRomName

        $core = Get-CoreByExt $ext
        $tagId = "g_$token"
        $finalLink = "https://rivegabry.github.io/emulatore-nfc/?tag=$tagId"
        $dateStr = (Get-Date).ToString("dd/MM/yyyy")

        $mapping[$tagId] = [ordered]@{
            originalName = $cleanTitle
            randomRom    = $randomRomName
            randomCover  = $randomImgName
            core         = $core
            link         = $finalLink
            date         = $dateStr
        }

        $newProcessed += $cleanTitle

        Write-Host "  [OK] ELABORATO: $cleanTitle" -ForegroundColor Green
        Write-Host "       Console:        $($core.ToUpper())" -ForegroundColor Gray
        Write-Host "       File ROM Cloud: roms/$randomRomName (protetto)" -ForegroundColor Gray
        if ($randomImgName) {
            Write-Host "       Copertina:      roms/$randomImgName (associata)" -ForegroundColor Gray
        } else {
            Write-Host "       Copertina:      (nessuna foto trovata con lo stesso nome)" -ForegroundColor DarkGray
        }
        Write-Host "       Link Tag NFC:   $finalLink" -ForegroundColor Gray
        Write-Host ""
    }

    # Salva mapping aggiornato
    $mapping | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $mappingFile -Encoding UTF8

} else {
    Write-Host "[1/3] Nessun nuovo file ROM trovato da randomizzare." -ForegroundColor DarkGray
    Write-Host "      (I file gia' randomizzati r_... sono gia' registrati)" -ForegroundColor DarkGray
    Write-Host ""
}

# 3. Aggiorna database.json nel repository per GitHub Pages
Write-Host "[2/3] Aggiornamento database.json per GitHub Pages..." -ForegroundColor Cyan
$dbTags = @()
foreach ($k in $mapping.Keys) {
    $item = $mapping[$k]
    $coverUrl = ""
    if ($item.randomCover) {
        $coverUrl = "https://rivegabry.github.io/emulatore-nfc/roms/$($item.randomCover)"
    }
    $romUrl = "https://rivegabry.github.io/emulatore-nfc/roms/$($item.randomRom)"
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
    app     = "dedalo-nfc"
    version = "1.0"
    tags    = $dbTags
}

$databasePath = Join-Path $scriptDir "database.json"
$dbObj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $databasePath -Encoding UTF8

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
