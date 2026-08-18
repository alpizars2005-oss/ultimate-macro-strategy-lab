param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [string]$MapName = '',
    [string]$TowerNames = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ua = 'UltimateMacroStrategyLab/0.2.5 (private development; TDS Wiki asset cache)'
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
    return Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent'=$ua; 'Accept'='application/json' } -TimeoutSec 25
}

function Remove-OldImageVariants([string]$BasePath) {
    foreach ($ext in @('.png','.jpg','.jpeg','.bmp')) {
        Remove-Item -LiteralPath ($BasePath + $ext) -Force -ErrorAction SilentlyContinue
    }
}

function Download-Image([string]$Url,[string]$BasePath) {
    $tmp = $BasePath + '.download'
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -PassThru -Headers @{ 'User-Agent'=$ua; 'Accept'='image/png,image/jpeg,image/*;q=0.8' } -TimeoutSec 45
    if (!(Test-Path -LiteralPath $tmp) -or (Get-Item -LiteralPath $tmp).Length -lt 200) {
        throw "Downloaded asset is empty: $Url"
    }

    $contentType = [string]$response.Headers['Content-Type']
    $ext = '.png'
    if ($contentType -match 'jpe?g') { $ext = '.jpg' }
    elseif ($contentType -match 'bmp') { $ext = '.bmp' }
    elseif ($contentType -match 'webp') {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw 'Wiki returned WebP; this build only caches Windows/GDI+ compatible PNG/JPEG assets.'
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
            $target = Download-Image $url (Join-Path $towerDir $key)
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
    try {
        $url = $null

        ; Current Fandom maps expose their interactive-map artwork through Map:<name>.
        ; Prefer that before scraping old gallery-style "Top Down" filenames.
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
            $target = Download-Image $url (Join-Path $mapDir $key)
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
