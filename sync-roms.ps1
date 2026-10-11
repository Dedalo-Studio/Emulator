# ============================================================
#  DEDALO GAME - Sincronizzatore Automatico & Randomizzatore ROM
# ============================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$romsDir = Join-Path $scriptDir "roms"
if (-not (Test-Path -LiteralPath $romsDir)) {
    New-Item -ItemType Directory -Path $romsDir | Out-Null
}

$mappingFile = Join-Path $romsDir "mapping.json"
$mapping = @{}
if (Test-Path -LiteralPath $mappingFile) {
    try {
        $jsonContent = Get-Content -LiteralPath $mappingFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $jsonContent.PSObject.Properties) {
            $mapping[$prop.Name] = $prop.Value
        }
    } catch {}
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

Write-Host "Scansione cartella roms in corso..." -ForegroundColor Cyan

$romFiles = Get-ChildItem -LiteralPath $romsDir -File | Where-Object {
    $ext = $_.Extension.ToLower()
    $name = $_.Name.ToLower()
    ($supportedExts -contains $ext) -and (-not $name.StartsWith("r_"))
}

$newCount = 0

foreach ($file in $romFiles) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $cleanTitle = $baseName.Replace('_', ' ').Trim()
    $ext = $file.Extension.ToLower()

    # Genera token crittografico casuale di 12 caratteri (impossibile da indovinare)
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

    # Rinomina la ROM con il nome casuale
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

    Write-Host "  [+] Registrato con successo: $cleanTitle" -ForegroundColor Green
    Write-Host "      ROM Protetta: $randomRomName" -ForegroundColor Gray
    Write-Host "      Link Tag NFC: $finalLink" -ForegroundColor Gray
    $newCount++
}

# Salva mapping aggiornato
$mapping | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $mappingFile -Encoding UTF8

# ── Genera database.json nel repository per GitHub Pages (Zero limiti, affidabilissimo) ──
$dbTags = @()
foreach ($k in $mapping.Keys) {
    $item = $mapping[$k]
    $coverUrl = ""
    if ($item.randomCover) {
        $coverUrl = "https://rivegabry.github.io/emulatore-nfc/roms/$($item.randomCover)"
    }
    $romUrl = "https://rivegabry.github.io/emulatore-nfc/roms/$($item.randomRom)"
    $linkUrl = $item.link
    $qrUrl = "https://api.qrserver.com/v1/create-qr-code/?size=220x220&margin=4&data=" + [System.Uri]::EscapeDataString($linkUrl)

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

# Rigenera il file di riepilogo per Gabry "I-MIEI-GIOCHI.txt"
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

Write-Host "OK: database.json aggiornato con $($dbTags.Count) giochi registrati." -ForegroundColor Green
Write-Host "Totale nuovi giochi randomizzati in questa sessione: $newCount" -ForegroundColor Yellow
