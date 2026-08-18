param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [string]$MapName = '',
    [string]$TowerNames = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Browser-like requests are substantially more reliable against Fandom's bot/CDN edge
# than a custom PowerShell user agent. Assets are still fetched only on demand.
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36 UltimateMacroStrategyLab/0.2.9'
$wikiRoot = 'https://tds.fandom.com'
$root = Join-Path $env:APPDATA 'Ultimate_Macro\StrategyEditor'
$towerDir = Join-Path $root 'TowerLibrary'
$mapDir = Join-Path $root 'MapLibrary\reference'
New-Item -ItemType Directory -Force -Path $towerDir,$mapDir | Out-Null

$logPath = Join-Path $root 'asset-sync.log'
$statusPath = Join-Path $root 'asset-sync-status.ini'
$towerOK = 0
$mapOK = 0
$misses = 0
$errors = 0
$apiFallbacks = 0
$downloadFallbacks = 0
$optimized = 0

function Log([string]$Text) {
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text)
}

function Safe-Key([string]$Value) {
    $key = $Value.Trim().ToLowerInvariant() -replace '[^a-z0-9]+','-'
    return $key.Trim('-')
}

function Read-Ini([string]$Path) {
    $result = [ordered]@{}
    $section = $null
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[(.+)\]$') {
            $section = $Matches[1].Trim()
            if (!$result.Contains($section)) { $result[$section] = [ordered]@{} }
            continue
        }
        if ($section -and $line -match '^([^=]+)=(.*)$') {
            $result[$section][$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    return $result
}

function Write-Status([string]$LastError='') {
    $safeError = ($LastError -replace '[\r\n]+',' ') -replace '=','-'
    $text = "[Sync]`r`nTowers=$towerOK`r`nMaps=$mapOK`r`nMisses=$misses`r`nErrors=$errors`r`nApiFallbacks=$apiFallbacks`r`nDownloadFallbacks=$downloadFallbacks`r`nOptimized=$optimized`r`nLastError=$safeError`r`nCompleted=$(Get-Date -Format o)`r`n"
    [IO.File]::WriteAllText($statusPath, $text, (New-Object Text.UTF8Encoding($false)))
}

# Never turn a click with no loaded strategy into a 20-asset catalog crawl.
if ([string]::IsNullOrWhiteSpace($MapName) -and [string]::IsNullOrWhiteSpace($TowerNames)) {
    Log 'sync SKIP: no strategy-scoped map/tower request'
    Write-Status 'Open a strategy before syncing assets.'
    exit 0
}

function Common-Headers([string]$Accept) {
    return @{
        'User-Agent' = $ua
        'Accept' = $Accept
        'Accept-Language' = 'en-US,en;q=0.9'
        'Referer' = "$wikiRoot/"
        'Cache-Control' = 'no-cache'
    }
}

function Build-WikiUri([hashtable]$Params) {
    $query = @{}
    foreach ($k in $Params.Keys) { $query[$k] = $Params[$k] }
    $query['format'] = 'json'
    $query['origin'] = '*'
    $pairs = foreach ($k in $query.Keys) {
        [Uri]::EscapeDataString([string]$k) + '=' + [Uri]::EscapeDataString([string]$query[$k])
    }
    return "$wikiRoot/api.php?" + ($pairs -join '&')
}

function Invoke-CurlText([string]$Url) {
    $tmp = Join-Path $env:TEMP ('ultimate-macro-wiki-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & curl.exe -L --fail --silent --show-error --compressed --connect-timeout 15 --max-time 45 `
            -A $ua -e "$wikiRoot/" -H 'Accept: application/json' -H 'Accept-Language: en-US,en;q=0.9' `
            -o $tmp $Url
        if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $tmp)) {
            throw "curl.exe failed with exit code $LASTEXITCODE"
        }
        return [IO.File]::ReadAllText($tmp)
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Wiki([hashtable]$Params) {
    $uri = Build-WikiUri $Params
    try {
        return Invoke-RestMethod -Uri $uri -Headers (Common-Headers 'application/json') -TimeoutSec 25
    } catch {
        $script:apiFallbacks++
        Log "api REST fallback -> curl :: $($_.Exception.Message)"
        $text = Invoke-CurlText $uri
        if ([string]::IsNullOrWhiteSpace($text)) { throw 'Fandom API returned an empty response.' }
        return ($text | ConvertFrom-Json)
    }
}

function Remove-OldImageVariants([string]$BasePath) {
    foreach ($ext in @('.png','.jpg','.jpeg','.bmp','.webp','.download')) {
        Remove-Item -LiteralPath ($BasePath + $ext) -Force -ErrorAction SilentlyContinue
    }
}

function Get-ImageKind([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) { return $null }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 8 -and
        $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47 -and
        $bytes[4] -eq 0x0D -and $bytes[5] -eq 0x0A -and $bytes[6] -eq 0x1A -and $bytes[7] -eq 0x0A) { return 'png' }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8 -and $bytes[2] -eq 0xFF) { return 'jpg' }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x42 -and $bytes[1] -eq 0x4D) { return 'bmp' }
    if ($bytes.Length -ge 12 -and
        $bytes[0] -eq 0x52 -and $bytes[1] -eq 0x49 -and $bytes[2] -eq 0x46 -and $bytes[3] -eq 0x46 -and
        $bytes[8] -eq 0x57 -and $bytes[9] -eq 0x45 -and $bytes[10] -eq 0x42 -and $bytes[11] -eq 0x50) { return 'webp' }
    return $null
}

function Save-Jpeg([System.Drawing.Bitmap]$Bitmap,[string]$Path,[int]$Quality) {
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
    $parameters = [System.Drawing.Imaging.EncoderParameters]::new(1)
    $parameters.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new(
        [System.Drawing.Imaging.Encoder]::Quality, [long]$Quality
    )
    try {
        $Bitmap.Save($Path, $codec, $parameters)
    } finally {
        $parameters.Dispose()
    }
}

function Optimize-Image([string]$InputPath,[string]$BasePath,[ValidateSet('tower','map')][string]$AssetType) {
    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Image]::FromFile($InputPath)
    $bitmap = $null
    $graphics = $null
    try {
        if ($AssetType -eq 'tower') {
            $maxW = 256
            $maxH = 256
            $quality = 86
        } else {
            # The editor never needs a multi-megapixel wiki image. This is plenty
            # for the 960px expanded canvas and keeps the AppData cache lightweight.
            $maxW = 1280
            $maxH = 720
            $quality = 82
        }

        $scale = [Math]::Min(1.0, [Math]::Min($maxW / [double]$image.Width, $maxH / [double]$image.Height))
        $newW = [Math]::Max(1, [int][Math]::Round($image.Width * $scale))
        $newH = [Math]::Max(1, [int][Math]::Round($image.Height * $scale))

        $bitmap = [System.Drawing.Bitmap]::new($newW, $newH)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([System.Drawing.Color]::FromArgb(23,23,23))
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($image, 0, 0, $newW, $newH)

        Remove-OldImageVariants $BasePath
        $target = $BasePath + '.jpg'
        Save-Jpeg $bitmap $target $quality
        $script:optimized++
        Log "optimized $AssetType $($image.Width)x$($image.Height) -> ${newW}x${newH} :: $target"
        return $target
    } finally {
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
        if ($image) { $image.Dispose() }
    }
}

function Download-Image([string]$Url,[string]$BasePath,[ValidateSet('tower','map')][string]$AssetType) {
    $tmp = $BasePath + '.download'
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    try {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp `
                -Headers (Common-Headers 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8') `
                -TimeoutSec 45 | Out-Null
        } catch {
            $script:downloadFallbacks++
            Log "image IWR fallback -> curl :: $($_.Exception.Message)"
            & curl.exe -L --fail --silent --show-error --compressed --connect-timeout 15 --max-time 60 `
                -A $ua -e "$wikiRoot/" -H 'Accept: image/avif,image/webp,image/apng,image/*,*/*;q=0.8' `
                -o $tmp $Url
            if ($LASTEXITCODE -ne 0) { throw "curl.exe image download failed with exit code $LASTEXITCODE" }
        }

        if (!(Test-Path -LiteralPath $tmp) -or (Get-Item -LiteralPath $tmp).Length -lt 200) {
            throw "Downloaded asset is empty: $Url"
        }

        $kind = Get-ImageKind $tmp
        if (!$kind) { throw 'Downloaded response is not an image (likely an HTML/CDN error response).' }
        if ($kind -eq 'webp') { throw 'Fandom returned WebP instead of the requested original image.' }

        try {
            return Optimize-Image $tmp $BasePath $AssetType
        } catch {
            # Optimization is a size feature, not a reason to lose an otherwise valid asset.
            Log "optimize fallback $AssetType :: $($_.Exception.Message)"
            Remove-OldImageVariants $BasePath
            $target = $BasePath + '.' + $kind
            Move-Item -LiteralPath $tmp -Destination $target -Force
            return $target
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Normalize-FileTitle([string]$Title) {
    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
    if ($Title.StartsWith('File:')) { return $Title }
    return 'File:' + $Title
}

function Get-PagePrimaryFile([string]$Page) {
    $json = Invoke-Wiki @{ action='query'; titles=$Page; prop='pageimages'; piprop='name' }
    foreach ($pageObj in $json.query.pages.PSObject.Properties.Value) {
        if ($pageObj.pageimage) { return Normalize-FileTitle ([string]$pageObj.pageimage) }
    }
    return $null
}

function Get-PageImages([string]$Page) {
    $json = Invoke-Wiki @{ action='query'; titles=$Page; prop='images'; imlimit='max' }
    $titles = @()
    foreach ($pageObj in $json.query.pages.PSObject.Properties.Value) {
        foreach ($img in @($pageObj.images)) {
            if ($img.title) { $titles += [string]$img.title }
        }
    }
    return $titles
}

function Get-ImageOriginalUrl([string]$FileTitle) {
    $fileTitle = Normalize-FileTitle $FileTitle
    if (!$fileTitle) { return $null }
    $json = Invoke-Wiki @{ action='query'; titles=$fileTitle; prop='imageinfo'; iiprop='url' }
    foreach ($pageObj in $json.query.pages.PSObject.Properties.Value) {
        $ii = @($pageObj.imageinfo)
        if ($ii.Count -gt 0 -and $ii[0].url) { return [string]$ii[0].url }
    }
    return $null
}

function Choose-DefaultTowerImage([string]$TowerName,[string[]]$Titles) {
    $norm = ($TowerName -replace '[^A-Za-z0-9]','').ToLowerInvariant()
    $ranked = foreach ($title in $Titles) {
        $name = $title -replace '^File:',''
        $flat = ($name -replace '[^A-Za-z0-9]','').ToLowerInvariant()
        $score = 0
        if ($flat.Contains($norm)) { $score += 45 }
        if ($name -match '(?i)default') { $score += 80 }
        if ($name -match '(?i)icon|render|portrait|static|dynamic') { $score += 35 }
        if ($name -match '(?i)golden|skin|crate|weapon|sound|ogg|gif|face|concept|upgrade|level[1-9]') { $score -= 100 }
        [PSCustomObject]@{Title=$title; Score=$score}
    }
    $best = $ranked | Sort-Object Score -Descending | Select-Object -First 1
    if ($best -and $best.Score -ge 70) { return [string]$best.Title }
    return $null
}

function Choose-TopDown([string]$MapName,[string[]]$Titles) {
    $norm = ($MapName -replace '[^A-Za-z0-9]','').ToLowerInvariant()
    $ranked = foreach ($title in $Titles) {
        $name = $title -replace '^File:',''
        $flat = ($name -replace '[^A-Za-z0-9]','').ToLowerInvariant()
        $score = 0
        if ($name -match '(?i)top[ _-]*down|topdown|overhead|bird.?s.?eye|interactive') { $score += 120 }
        if ($name -match '(?i)map') { $score += 35 }
        if ($flat.Contains($norm)) { $score += 40 }
        if ($name -match '(?i)icon|logo|thumbnail|badge|old|legacy') { $score -= 90 }
        [PSCustomObject]@{Title=$title; Score=$score}
    }
    $best = $ranked | Sort-Object Score -Descending | Select-Object -First 1
    if ($best -and $best.Score -ge 100) { return [string]$best.Title }
    return $null
}

$lastError = ''

$towerCatalog = Read-Ini (Join-Path $InstallDir 'Resources\StrategyLab\Towers\catalog.ini')
$towerSections = @()
if (![string]::IsNullOrWhiteSpace($TowerNames)) {
    $towerSections = @($TowerNames.Split('|') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
}

foreach ($section in $towerSections) {
    $info = if ($towerCatalog.Contains($section)) { $towerCatalog[$section] } else { $null }
    $display = if ($info -and $info.Contains('display')) { $info['display'] } else { $section }
    $page = if ($info -and $info.Contains('wikiPage')) { $info['wikiPage'] } else { $display }
    $key = Safe-Key $section
    try {
        $url = $null
        $galleryTitles = @(Get-PageImages ($page + '/Gallery'))
        $defaultFile = Choose-DefaultTowerImage $display $galleryTitles
        if ($defaultFile) {
            $url = Get-ImageOriginalUrl $defaultFile
            if ($url) { Log "tower DEFAULT $display [$defaultFile]" }
        }
        if (!$url) {
            $primary = Get-PagePrimaryFile $page
            if ($primary) { $url = Get-ImageOriginalUrl $primary }
        }
        if (!$url) {
            $primary = Get-PagePrimaryFile ($page + '/Gallery')
            if ($primary) { $url = Get-ImageOriginalUrl $primary }
        }

        if ($url) {
            $target = Download-Image $url (Join-Path $towerDir $key) 'tower'
            $towerOK++
            Log "tower OK $display -> $target"
        } else {
            $misses++
            Log "tower MISS $display (no suitable portrait discovered)"
        }
    } catch {
        $errors++
        $lastError = "tower $display :: $($_.Exception.Message)"
        Log "tower ERROR $display :: $($_.Exception.Message)"
    }
}

if (![string]::IsNullOrWhiteSpace($MapName)) {
    $mapCatalog = Read-Ini (Join-Path $InstallDir 'Resources\StrategyLab\Maps\catalog.ini')
    $section = $MapName.Trim()
    $info = if ($mapCatalog.Contains($section)) { $mapCatalog[$section] } else { $null }
    $display = if ($info -and $info.Contains('display')) { $info['display'] } else { $section }
    $page = if ($info -and $info.Contains('wikiPage')) { $info['wikiPage'] } else { $display }
    $key = Safe-Key $section
    try {
        $url = $null
        $titles = @()
        try { $titles += @(Get-PageImages $page) } catch { Log "map page images miss $page" }
        try { $titles += @(Get-PageImages ('Map:' + $page)) } catch { Log "interactive map images miss $page" }
        $file = Choose-TopDown $display @($titles | Select-Object -Unique)
        if ($file) { $url = Get-ImageOriginalUrl $file }

        if (!$url) {
            $primary = Get-PagePrimaryFile ('Map:' + $page)
            if ($primary) { $url = Get-ImageOriginalUrl $primary }
        }

        if ($url) {
            $target = Download-Image $url (Join-Path $mapDir $key) 'map'
            $mapOK++
            Log "map OK $display -> $target"
        } else {
            $misses++
            Log "map MISS $display (no top-down/interactive image discovered)"
        }
    } catch {
        $errors++
        $lastError = "map $display :: $($_.Exception.Message)"
        Log "map ERROR $display :: $($_.Exception.Message)"
    }
}

Write-Status $lastError
$markerName = if (![string]::IsNullOrWhiteSpace($MapName)) {
    'asset-sync-' + (Safe-Key $MapName) + '.done'
} else {
    'asset-sync-strategy.done'
}
[IO.File]::WriteAllText((Join-Path $root $markerName), (Get-Date -Format 'o'), (New-Object Text.UTF8Encoding($false)))
