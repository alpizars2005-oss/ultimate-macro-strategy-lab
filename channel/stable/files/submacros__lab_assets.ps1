param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [string]$MapName = '',
    [string]$TowerNames = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ua = 'UltimateMacroStrategyLab/0.2.6 (private development; TDS Wiki asset cache)'
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

function Invoke-Wiki([hashtable]$Params) {
    $query = @{}
    foreach ($k in $Params.Keys) { $query[$k] = $Params[$k] }
    $query['format'] = 'json'
    $pairs = foreach ($k in $query.Keys) {
        [Uri]::EscapeDataString([string]$k) + '=' + [Uri]::EscapeDataString([string]$query[$k])
    }
    $uri = 'https://tds.fandom.com/api.php?' + ($pairs -join '&')

    try {
        return Invoke-RestMethod -UseBasicParsing -Uri $uri -Headers @{ 'User-Agent'=$ua; 'Accept'='application/json' } -TimeoutSec 25
    } catch {
        $primary = $_.Exception.Message
        Log "wiki REST fallback :: $primary"
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if (!$curl) { throw "TDS Wiki request failed and curl.exe is unavailable: $primary" }

        $raw = & curl.exe -L --fail --silent --show-error --max-time 25 -A $ua -H 'Accept: application/json' $uri 2>&1
        if ($LASTEXITCODE -ne 0) { throw "TDS Wiki request failed via PowerShell and curl.exe: $($raw -join ' ')" }
        $text = ($raw -join "`n")
        if ([string]::IsNullOrWhiteSpace($text)) { throw 'TDS Wiki returned an empty response.' }
        return $text | ConvertFrom-Json
    }
}

function Remove-OldImageVariants([string]$BasePath) {
    foreach ($ext in @('.png','.jpg','.jpeg','.bmp','.webp')) {
        Remove-Item -LiteralPath ($BasePath + $ext) -Force -ErrorAction SilentlyContinue
    }
}

function Get-ImageExtension([string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 12) { return $null }
    if ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) { return '.png' }
    if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8 -and $bytes[2] -eq 0xFF) { return '.jpg' }
    if ($bytes[0] -eq 0x42 -and $bytes[1] -eq 0x4D) { return '.bmp' }
    if ([Text.Encoding]::ASCII.GetString($bytes,0,4) -eq 'RIFF' -and [Text.Encoding]::ASCII.GetString($bytes,8,4) -eq 'WEBP') { return '.webp' }
    return $null
}

function Remove-InvalidCachedVariants([string]$BasePath) {
    foreach ($ext in @('.png','.jpg','.jpeg','.bmp','.webp')) {
        $path = $BasePath + $ext
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $actual = Get-ImageExtension $path
        if (!$actual -or $actual -eq '.webp') {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            Log "cache PURGE $path (invalid/unsupported image bytes)"
        }
    }
}

function Download-Image([string]$Url,[string]$BasePath) {
    $tmp = $BasePath + '.download'
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -Headers @{ 'User-Agent'=$ua; 'Accept'='image/png,image/jpeg,image/*;q=0.8' } -TimeoutSec 45 | Out-Null
    } catch {
        $primary = $_.Exception.Message
        Log "image REST fallback :: $primary"
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if (!$curl) { throw "Image download failed and curl.exe is unavailable: $primary" }
        $raw = & curl.exe -L --fail --silent --show-error --max-time 45 -A $ua -H 'Accept: image/png,image/jpeg,image/*;q=0.8' -o $tmp $Url 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Image download failed via PowerShell and curl.exe: $($raw -join ' ')" }
    }

    if (!(Test-Path -LiteralPath $tmp) -or (Get-Item -LiteralPath $tmp).Length -lt 200) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw "Downloaded asset is empty: $Url"
    }

    $ext = Get-ImageExtension $tmp
    if (!$ext) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw 'Downloaded response is not a supported image (possibly an HTML/error response).'
    }
    if ($ext -eq '.webp') {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw 'Image source returned WebP; Windows GDI+ cannot render it safely in this Lab build.'
    }

    Remove-OldImageVariants $BasePath
    $target = $BasePath + $ext
    Move-Item -LiteralPath $tmp -Destination $target -Force
    return $target
}

function Get-PageThumbnail([string]$Page,[int]$Width=128) {
    $json = Invoke-Wiki @{ action='query'; titles=$Page; prop='pageimages'; piprop='thumbnail'; pithumbsize=$Width }
    foreach ($pageObj in $json.query.pages.PSObject.Properties.Value) {
        if ($pageObj.thumbnail -and $pageObj.thumbnail.source) { return [string]$pageObj.thumbnail.source }
    }
    return $null
}

function Get-PageImages([string]$Page) {
    $json = Invoke-Wiki @{ action='query'; titles=$Page; prop='images'; imlimit='max' }
    $titles = @()
    foreach ($pageObj in $json.query.pages.PSObject.Properties.Value) {
        foreach ($img in @($pageObj.images)) { if ($img.title) { $titles += [string]$img.title } }
    }
    return $titles
}

function Get-ImageThumbnail([string]$FileTitle,[int]$Width=1280) {
    $json = Invoke-Wiki @{ action='query'; titles=$FileTitle; prop='imageinfo'; iiprop='url'; iiurlwidth=$Width }
    foreach ($pageObj in $json.query.pages.PSObject.Properties.Value) {
        $ii = @($pageObj.imageinfo)
        if ($ii.Count -gt 0) {
            if ($ii[0].thumburl) { return [string]$ii[0].thumburl }
            if ($ii[0].url) { return [string]$ii[0].url }
        }
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
        if ($name -match '(?i)icon|render|portrait|static|dynamic') { $score += 25 }
        if ($name -match '(?i)golden|skin|crate|weapon|sound|ogg|gif|face|concept|upgrade|level[1-9]') { $score -= 90 }
        [PSCustomObject]@{Title=$title; Score=$score}
    }
    $best = $ranked | Sort-Object Score -Descending | Select-Object -First 1
    if ($best -and $best.Score -ge 100) { return [string]$best.Title }
    return $null
}

function Choose-TopDown([string]$MapName,[string[]]$Titles) {
    $norm = ($MapName -replace '[^A-Za-z0-9]','').ToLowerInvariant()
    $ranked = foreach ($title in $Titles) {
        $name = $title -replace '^File:',''
        $flat = ($name -replace '[^A-Za-z0-9]','').ToLowerInvariant()
        $score = 0
        if ($name -match '(?i)top[ _-]*down|topdown|overhead|bird.?s.?eye|map') { $score += 100 }
        if ($flat.Contains($norm)) { $score += 30 }
        if ($name -match '(?i)icon|logo|thumbnail|badge') { $score -= 80 }
        [PSCustomObject]@{Title=$title; Score=$score}
    }
    $best = $ranked | Sort-Object Score -Descending | Select-Object -First 1
    if ($best -and $best.Score -ge 100) { return [string]$best.Title }
    return $null
}

function Write-Status {
    $text = "[Sync]`r`nTowers=$towerOK`r`nMaps=$mapOK`r`nMisses=$misses`r`nErrors=$errors`r`nCompleted=$(Get-Date -Format o)`r`n"
    [IO.File]::WriteAllText($statusPath, $text, (New-Object Text.UTF8Encoding($false)))
}

$towerCatalogPath = Join-Path $InstallDir 'Resources\StrategyLab\Towers\catalog.ini'
$towerCatalog = Read-Ini $towerCatalogPath
$towerSections = @()
if (![string]::IsNullOrWhiteSpace($TowerNames)) {
    $towerSections = @($TowerNames.Split('|') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} else {
    $towerSections = @($towerCatalog.Keys)
}
foreach ($section in $towerSections) {
    $info = if ($towerCatalog.Contains($section)) { $towerCatalog[$section] } else { $null }
    $display = if ($info -and $info.Contains('display')) { $info['display'] } else { $section }
    $page = if ($info -and $info.Contains('wikiPage')) { $info['wikiPage'] } else { $display }
    $key = Safe-Key $section
    $base = Join-Path $towerDir $key
    Remove-InvalidCachedVariants $base
    try {
        $url = $null
        $galleryTitles = @(Get-PageImages ($page + '/Gallery'))
        $defaultFile = Choose-DefaultTowerImage $display $galleryTitles
        if ($defaultFile) {
            $url = Get-ImageThumbnail $defaultFile 192
            if ($url) { Log "tower DEFAULT $display [$defaultFile]" }
        }
        if (!$url) { $url = Get-PageThumbnail $page 192 }
        if (!$url) { $url = Get-PageThumbnail ($page + '/Gallery') 192 }

        if ($url) {
            $target = Download-Image $url $base
            $towerOK++
            Log "tower OK $display -> $target"
        } else {
            $misses++
            Log "tower MISS $display (no suitable default portrait)"
        }
    } catch {
        $errors++
        Log "tower ERROR $display :: $($_.Exception.Message)"
    }
}

$mapCatalogPath = Join-Path $InstallDir 'Resources\StrategyLab\Maps\catalog.ini'
$mapCatalog = Read-Ini $mapCatalogPath
$mapSections = if (![string]::IsNullOrWhiteSpace($MapName)) { @($MapName.Trim()) } else { @($mapCatalog.Keys) }
foreach ($section in $mapSections) {
    $info = if ($mapCatalog.Contains($section)) { $mapCatalog[$section] } else { $null }
    $display = if ($info -and $info.Contains('display')) { $info['display'] } else { $section }
    $page = if ($info -and $info.Contains('wikiPage')) { $info['wikiPage'] } else { $display }
    $key = Safe-Key $section
    $base = Join-Path $mapDir $key
    Remove-InvalidCachedVariants $base
    try {
        $url = $null
        $url = Get-PageThumbnail ('Map:' + $page) 1280

        if (!$url) {
            $titles = @(Get-PageImages $page)
            $file = Choose-TopDown $display $titles
            if (!$file) {
                $titles = @(Get-PageImages ('Map:' + $page))
                $file = Choose-TopDown $display $titles
            }
            if ($file) { $url = Get-ImageThumbnail $file 1280 }
        }

        if ($url) {
            $target = Download-Image $url $base
            $mapOK++
            Log "map OK $display -> $target"
        } else {
            $misses++
            Log "map MISS $display (no current interactive/top-down image discovered)"
        }
    } catch {
        $errors++
        Log "map ERROR $display :: $($_.Exception.Message)"
    }
}

Write-Status
$markerName = if (![string]::IsNullOrWhiteSpace($MapName)) { 'asset-sync-' + (Safe-Key $MapName) + '.done' } else { 'asset-sync-catalog.done' }
[IO.File]::WriteAllText((Join-Path $root $markerName), (Get-Date -Format 'o'), (New-Object Text.UTF8Encoding($false)))
Log "asset sync complete towers=$towerOK maps=$mapOK misses=$misses errors=$errors"
exit 0
