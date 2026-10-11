# ============================================================
#  DEDALO GAME - Sincronizzatore Automatico & Randomizzatore ROM
# ============================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$romsDir = Join-Path $scriptDir "roms"
if (-not (Test-Path $romsDir)) {
    New-Item -ItemType Directory -Path $romsDir | Out-Null
}

$mappingFile = Join-Path $romsDir "mapping.json"
$mapping = @{}
if (Test-Path $mappingFile) {
    try {
        $jsonContent = Get-Content $mappingFile -Raw -Encoding UTF8 | ConvertFrom-Json
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

$romFiles = Get-ChildItem -Path $romsDir -File | Where-Object {
    $ext = $_.Extension.ToLower()
    $name = $_.Name.ToLower()
    ($supportedExts -contains $ext) -and (-not $name.StartsWith("r_"))
}

$newCount = 0
$newTags = @()

foreach ($file in $romFiles) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $cleanTitle = $baseName.Replace('_', ' ').Trim()
    $ext = $file.Extension.ToLower()

    # Genera token crittografico casuale di 12 caratteri (impossibile da indovinare)
    $token = [System.Guid]::NewGuid().ToString('N').Substring(0, 12)
    $randomRomName = "r_$token$ext"

    # Cerca eventuale immagine di copertina associata (stesso nome file)
    $coverUrl = ""
    $randomImgName = ""
    foreach ($imgExt in $imageExts) {
        $candidateImg = Join-Path $romsDir "$baseName$imgExt"
        if (Test-Path $candidateImg) {
            $randomImgName = "cov_$token$imgExt"
            $destImgPath = Join-Path $romsDir $randomImgName
            Rename-Item -Path $candidateImg -NewName $randomImgName
            $coverUrl = "https://rivegabry.github.io/emulatore-nfc/roms/$randomImgName"
            break
        }
    }

    # Rinomina la ROM con il nome casuale
    $destRomPath = Join-Path $romsDir $randomRomName
    Rename-Item -Path $file.FullName -NewName $randomRomName

    $core = Get-CoreByExt $ext
    $tagId = "g_$token"
    $romUrl = "https://rivegabry.github.io/emulatore-nfc/roms/$randomRomName"
    $finalLink = "https://rivegabry.github.io/emulatore-nfc/?tag=$tagId"
    $qrUrl = "https://api.qrserver.com/v1/create-qr-code/?size=220x220&margin=4&data=" + [System.Uri]::EscapeDataString($finalLink)
    $dateStr = (Get-Date).ToString("dd/MM/yyyy")

    $newTagObj = [ordered]@{
        id         = $tagId
        name       = $cleanTitle
        core       = $core
        rom        = $romUrl
        cover      = $coverUrl
        shader     = "crt-easymode.glslp"
        link       = $finalLink
        directLink = $finalLink
        qr         = $qrUrl
        date       = $dateStr
    }

    $newTags += $newTagObj

    $mapping[$tagId] = [ordered]@{
        originalName = $cleanTitle
        randomRom    = $randomRomName
        randomCover  = $randomImgName
        core         = $core
        link         = $finalLink
        date         = $dateStr
    }

    Write-Host "  [+] Registrato: $cleanTitle" -ForegroundColor Green
    Write-Host "      ROM Protetta: $randomRomName" -ForegroundColor Gray
    Write-Host "      Link Tag NFC: $finalLink" -ForegroundColor Gray
    $newCount++
}

# Salva mapping aggiornato
$mapping | ConvertTo-Json -Depth 5 | Set-Content -Path $mappingFile -Encoding UTF8

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
Set-Content -Path $summaryPath -Value ($sb.ToString()) -Encoding UTF8

# Se ci sono nuovi giochi, sincronizza con il database Cloud (api.restful-api.dev)
if ($newCount -gt 0) {
    Write-Host ""
    Write-Host "Sincronizzazione Cloud Database (api.restful-api.dev)..." -ForegroundColor Cyan
    try {
        $cloudUrl = "https://api.restful-api.dev/objects/ff808181a09d98f701a12cdfddb940c5"
        $currentDb = Invoke-RestMethod -Uri $cloudUrl -Method Get -TimeoutSec 10
        $existingTags = @()
        if ($currentDb.data -and $currentDb.data.tags) {
            $existingTags = [array]$currentDb.data.tags
        }

        # Rimuovi eventuali duplicati con gli stessi ID
        $newIds = $newTags | ForEach-Object { $_.id }
        $filtered = $existingTags | Where-Object { $newIds -notcontains $_.id }

        # Unisci nuovi tag all'inizio
        $allTags = @($newTags) + @($filtered)

        $putBody = @{
            name = "dedalo_tags_db"
            data = @{
                app  = "dedalo-nfc"
                tags = $allTags
            }
        } | ConvertTo-Json -Depth 6

        # Salva sul cloud
        $tempJson = Join-Path $scriptDir "temp_put.json"
        Set-Content -Path $tempJson -Value $putBody -Encoding UTF8
        curl.exe -s -X PUT $cloudUrl -H "Content-Type: application/json" -d "@$tempJson" | Out-Null
        Remove-Item -Path $tempJson -Force -ErrorAction SilentlyContinue

        Write-Host "OK: Database Cloud aggiornato con successo! I tag sono pronti nella sezione 'I Miei Tag'." -ForegroundColor Green
    } catch {
        Write-Warning "Impossibile aggiornare subito il cloud: $_"
    }
}

Write-Host ""
Write-Host "Totale nuovi giochi randomizzati: $newCount" -ForegroundColor Yellow
