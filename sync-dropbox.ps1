# ======================================================================
#  DEDALO GAME - Sincronizzatore Automatico da Dropbox a GitHub Pages
# ======================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "         DEDALO GAME - SINCRONIZZATORE CATALOGO DA DROPBOX            " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$romsDir = Join-Path $scriptDir "roms"
if (-not (Test-Path -LiteralPath $romsDir)) {
    New-Item -ItemType Directory -Path $romsDir | Out-Null
}

$dropboxFolderUrl = "https://www.dropbox.com/scl/fo/t3ug2kmdl478qkxiuj529/AMUw7v86c4PJzb4UHECWLMs?rlkey=l6ynr2p3bvnxowkthffym9yfd&st=elpaii6b&dl=1"
$githubRepo       = "Dedalo-Studio/Emulator"
$baseUrl          = "https://dedalo-studio.github.io/Emulator/"

# Carica token GitHub dal file locale ignorato da git
$tokenFile = Join-Path $scriptDir ".github-token"
$githubToken = ""
if (Test-Path -LiteralPath $tokenFile) {
    $githubToken = (Get-Content -LiteralPath $tokenFile -Raw -Encoding UTF8).Trim()
} elseif ($env:GH_TOKEN) {
    $githubToken = $env:GH_TOKEN
}

# ── 1. Carica Mapping Esistente ──
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

# ── 2. Download Catalogo da Dropbox ──
Write-Host "[1/4] Connessione a Dropbox e download catalogo..." -ForegroundColor Cyan

$tempZip     = Join-Path $env:TEMP "dedalo_dropbox_sync_$([System.Guid]::NewGuid().ToString('N')).zip"
$tempExtract = Join-Path $env:TEMP "dedalo_dropbox_extract_$([System.Guid]::NewGuid().ToString('N'))"

try {
    # Download archivio zip completo della cartella principale Dropbox
    curl.exe -s -L "$dropboxFolderUrl" -o "$tempZip"

    if (-not (Test-Path -LiteralPath $tempZip) -or ((Get-Item $tempZip).Length -lt 1000)) {
        throw "Download da Dropbox non riuscito o file non valido."
    }

    $zipSizeMb = [math]::Round(((Get-Item $tempZip).Length / 1MB), 2)
    Write-Host "      Download completato con successo ($zipSizeMb MB)." -ForegroundColor Gray

    # Estrazione
    Write-Host "[2/4] Analisi cartelle dei giochi..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $tempExtract | Out-Null
    Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force

} catch {
    Write-Host ""
    Write-Host "ERRORE DURANTE IL DOWNLOAD DA DROPBOX:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if (Test-Path -LiteralPath $tempZip) { Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $tempExtract) { Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
    pause
    return
}

# Funzione per determinare il core dell'emulatore dall'estensione
function Get-CoreByExt($ext) {
    switch ($ext.ToLower()) {
        ".gb"   { return "gb" }
        ".gbc"  { return "gb" }
        ".gba"  { return "gba" }
        ".nes"  { return "nes" }
        ".snes" { return "snes" }
        ".smc"  { return "snes" }
        ".sfc"  { return "snes" }
        ".n64"  { return "n64" }
        ".z64"  { return "n64" }
        ".v64"  { return "n64" }
        ".nds"  { return "nds" }
        ".md"   { return "segaMD" }
        ".bin"  { return "segaMD" }
        ".gen"  { return "segaMD" }
        ".pce"  { return "pce" }
        default { return "gba" }
    }
}

function New-RandomToken {
    $chars = "abcdefghjkmnpqrstuvwxyz23456789"
    $rand = New-Object System.Random
    $token = ""
    for ($i = 0; $i -lt 10; $i++) {
        $token += $chars[$rand.Next(0, $chars.Length)]
    }
    return $token
}

$romExtensions = @('.gb', '.gbc', '.gba', '.nes', '.snes', '.smc', '.sfc', '.n64', '.z64', '.v64', '.nds', '.md', '.bin', '.gen', '.pce')
$imgExtensions = @('.jpg', '.jpeg', '.png', '.webp')

# Trova tutte le cartelle di gioco (primo livello dentro l'estrazione)
$gameDirs = Get-ChildItem -LiteralPath $tempExtract -Directory

if ($gameDirs.Count -eq 0) {
    # Nel caso i file siano estratti senza una sottocartella intermedia
    $gameDirs = @(Get-Item -LiteralPath $tempExtract)
}

$syncedCount = 0
$newGames = @()

foreach ($dir in $gameDirs) {
    $gameFolder = $dir.FullName
    $folderName = $dir.Name.Trim()

    # Cerca la ROM nella cartella
    $romFile = Get-ChildItem -LiteralPath $gameFolder -File | Where-Object { $romExtensions -contains $_.Extension.ToLower() } | Select-Object -First 1
    if (-not $romFile) {
        # Controlla ricorsivamente
        $romFile = Get-ChildItem -LiteralPath $gameFolder -Recurse -File | Where-Object { $romExtensions -contains $_.Extension.ToLower() } | Select-Object -First 1
    }

    if (-not $romFile) {
        Write-Host "  [SALTO] Nessuna ROM trovata nella cartella '$folderName'" -ForegroundColor DarkGray
        continue
    }

    # Cerca la Copertina nella cartella
    $coverFile = Get-ChildItem -LiteralPath $gameFolder -File | Where-Object { $imgExtensions -contains $_.Extension.ToLower() } | Select-Object -First 1
    if (-not $coverFile) {
        $coverFile = Get-ChildItem -LiteralPath $gameFolder -Recurse -File | Where-Object { $imgExtensions -contains $_.Extension.ToLower() } | Select-Object -First 1
    }

    # Determina Nome Pulito e Token
    $cleanTitle = $folderName
    $token = $null
    $tagId = $null

    # Verifica se il file ha già un token di 10 caratteri (es. "Pokemon Blu 4e31fe0a78.gbc")
    $romBaseName = [System.IO.Path]::GetFileNameWithoutExtension($romFile.Name)
    if ($romBaseName -match '^(.+?)\s+([a-z0-9]{10})$') {
        $cleanTitle = $matches[1].Trim()
        $token = $matches[2]
        $tagId = "g_$token"
    } else {
        # Cerca se questo gioco esiste già nel mapping precedente per non cambiare il link NFC
        foreach ($k in $mapping.Keys) {
            if ($mapping[$k].originalName -eq $cleanTitle) {
                $tagId = $k
                $token = $k.Replace("g_", "")
                break
            }
        }
    }

    if (-not $token) {
        $token = New-RandomToken
        $tagId = "g_$token"
    }

    $ext = $romFile.Extension.ToLower()
    $core = Get-CoreByExt $ext
    $dateStr = (Get-Date).ToString("dd/MM/yyyy")

    $targetRomName = "$cleanTitle $token$ext"
    $targetRomPath = Join-Path $romsDir $targetRomName

    # Copia ROM
    Copy-Item -LiteralPath $romFile.FullName -Destination $targetRomPath -Force

    # Copia Copertina se presente
    $targetCoverName = ""
    if ($coverFile) {
        $covExt = $coverFile.Extension.ToLower()
        $targetCoverName = "$cleanTitle $token$covExt"
        $targetCoverPath = Join-Path $romsDir $targetCoverName
        Copy-Item -LiteralPath $coverFile.FullName -Destination $targetCoverPath -Force
    }

    $finalLink = "${baseUrl}?tag=${tagId}"

    $mapping[$tagId] = [ordered]@{}
    $mapping[$tagId].originalName = $cleanTitle
    $mapping[$tagId].randomRom    = $targetRomName
    $mapping[$tagId].randomCover  = $targetCoverName
    $mapping[$tagId].core         = $core
    $mapping[$tagId].link         = $finalLink
    $mapping[$tagId].date         = $dateStr

    $syncedCount++
    $newGames += "$cleanTitle [$($core.ToUpper())]"

    Write-Host "  [OK] $cleanTitle" -ForegroundColor Green
    Write-Host "       Console:     $($core.ToUpper())" -ForegroundColor Gray
    Write-Host "       File ROM:    roms/$targetRomName" -ForegroundColor Gray
    if ($targetCoverName) {
        Write-Host "       Copertina:   roms/$targetCoverName" -ForegroundColor Gray
    }
    Write-Host "       Link NFC:    $finalLink" -ForegroundColor DarkCyan
    Write-Host ""
}

# Pulizia temporanei
Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

# ── 3. Salva Mapping e Genera database.json per GitHub Pages ──
Write-Host "[3/4] Generazione database.json e catalogo..." -ForegroundColor Cyan

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($mappingFile, ($mapping | ConvertTo-Json -Depth 5), $utf8NoBom)

$dbTags = @()
foreach ($k in $mapping.Keys) {
    $item = $mapping[$k]
    $coverUrl = ""
    if ($item.randomCover) {
        $encodedCover = [System.Uri]::EscapeUriString($item.randomCover)
        $coverUrl = "${baseUrl}roms/$encodedCover"
    }
    $encodedRom = [System.Uri]::EscapeUriString($item.randomRom)
    $romUrl = "${baseUrl}roms/$encodedRom"
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
    updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    tags      = $dbTags
}

$dbPath = Join-Path $scriptDir "database.json"
[System.IO.File]::WriteAllText($dbPath, ($dbObj | ConvertTo-Json -Depth 5), $utf8NoBom)

# Genera riepilogo testuale I-MIEI-GIOCHI.txt
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("======================================================================")
[void]$sb.AppendLine("                   DEDALO GAME - I MIEI TAG NFC                       ")
[void]$sb.AppendLine("                 Generato il: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')")
[void]$sb.AppendLine("======================================================================")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("COME SCRIVERE IL TAG NFC:")
[void]$sb.AppendLine(" 1. Apri l'app 'NFC Tools' su smartphone (iOS o Android).")
[void]$sb.AppendLine(" 2. Vai su 'Scrivi' -> 'Aggiungi un record' -> 'URL / URI'.")
[void]$sb.AppendLine(" 3. Incolla il 'Link NFC Chip' del gioco scelto.")
[void]$sb.AppendLine(" 4. Tocca 'Scrivi' e avvicina il chip NFC al retro del telefono.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("======================================================================")
[void]$sb.AppendLine("")

foreach ($item in $dbTags) {
    [void]$sb.AppendLine("Gioco:          $($item.name)")
    [void]$sb.AppendLine("Console:        $($item.core.ToUpper())")
    [void]$sb.AppendLine("Link NFC Chip:  $($item.link)")
    [void]$sb.AppendLine("Link Diretto:   $($item.directLink)")
    if ($item.cover) {
        [void]$sb.AppendLine("Copertina:      $($item.cover)")
    }
    [void]$sb.AppendLine("Data:           $($item.date)")
    [void]$sb.AppendLine("----------------------------------------------------------------------")
    [void]$sb.AppendLine("")
}

$summaryPath = Join-Path $scriptDir "I-MIEI-GIOCHI.txt"
Set-Content -LiteralPath $summaryPath -Value ($sb.ToString()) -Encoding UTF8

# ── 4. Git Commit & Push su GitHub Pages (Dedalo-Studio/Emulator) ──
Write-Host "[4/4] Sincronizzazione su GitHub Pages..." -ForegroundColor Cyan

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
        if (Test-Path $c) { $gitCmd = $c; $gitFound = $true; break }
    }
}

if ($gitFound) {
    $status = & $gitCmd status --porcelain 2>&1
    if ([string]::IsNullOrWhiteSpace($status)) {
        Write-Host ""
        Write-Host "======================================================================" -ForegroundColor Green
        Write-Host "  TUTTO GIA' AGGIORNATO!" -ForegroundColor Green
        Write-Host "  Tutti i tuoi $($mapping.Count) giochi sono sincronizzati su GitHub!" -ForegroundColor Green
        Write-Host "======================================================================" -ForegroundColor Green
    } else {
        & $gitCmd add -A
        $msg = "Sincronizzazione catalogo da Dropbox: " + ($newGames -join ", ")
        if ($newGames.Count -eq 0) { $msg = "Sincronizzazione catalogo Dropbox" }
        & $gitCmd commit -m $msg 2>&1 | Out-Null

        $authUrl = "https://Dedalo-Studio:$githubToken@github.com/$githubRepo.git"
        & $gitCmd remote set-url origin $authUrl 2>&1 | Out-Null
        $pushOutput = & $gitCmd push origin main 2>&1
        $pushSuccess = $LASTEXITCODE -eq 0

        # Ripristina sempre l'URL pulito nel remote locale
        & $gitCmd remote set-url origin "https://github.com/$githubRepo.git" 2>&1 | Out-Null

        if ($pushSuccess) {
            Write-Host ""
            Write-Host "======================================================================" -ForegroundColor Green
            Write-Host "  SINCRONIZZAZIONE DA DROPBOX COMPLETATA CON SUCCESSO!" -ForegroundColor Green
            Write-Host "  I seguenti giochi sono ora ONLINE sul sito Dedalo Game:" -ForegroundColor Green
            foreach ($k in $mapping.Keys) {
                $g = $mapping[$k]
                Write-Host "   - $($g.originalName) [$($g.core.ToUpper())]" -ForegroundColor White
            }
            Write-Host ""
            Write-Host "  Apri il tuo Studio per visualizzare i tag e i codici QR:" -ForegroundColor Yellow
            Write-Host "  $baseUrl" -ForegroundColor Cyan
            Write-Host "======================================================================" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "ERRORE DURANTE L'INVIO A GITHUB:" -ForegroundColor Red
            Write-Host $pushOutput -ForegroundColor Red
        }
    }
}

Write-Host ""
