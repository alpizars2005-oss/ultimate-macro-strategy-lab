param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [string]$MapName = '',
    [string]$TowerNames = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ua = 'UltimateMacroStrategyLab/0.2.7 (private development; TDS Wiki asset cache)'
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

function Build-WikiUri([hashtable]$Params) {
    $query = @{}
    foreach ($k in $Params.Keys) { $query[$k] = $Params[$k] }
    $query['format'] = 'json'
    $pairs = foreach ($k in $query.Keys) {
        [Uri]::EscapeDataString([string]$k) + '=' + [Uri]::EscapeDataString([string]$query[$k])
    }
    return 'https://tds.fandom.com/api.php?' + ($pairs -join '&')
}

function Invoke-CurlText([string]$Url) {
    $tmp = Join-Path $env:TEMP ('ultimate-macro-wiki-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & curl.exe -L --fail --silent --show-error --connect-timeout 15 --max-time 45 `
            -A $ua -H 'Accept: application/json' -o $tmp $Url
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
        return Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent'=$ua; 'Accept'='application/json' } -TimeoutSec 25
    } catch {
        $script:apiFallbacks++
        Log "api REST fallback -> curl :: $($_.Exception.Message)"
        $text = Invoke-CurlText $uri
        return ($text | ConvertFrom-Json)
    }
}

function Remove-OldImageVariants([string]$BasePath) {
    foreach ($ext in @('.png','.jpg','.jpeg','.bmp','.webp')) {
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

function Download-Image([string]$Url,[string]$BasePath) {
    $tmp = $BasePath + '.download'
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    try {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp `
                -Headers @{ 'User-Agent'=$ua; 'Accept'='image/png,image/jpeg,image/bmp,image/*;q=0.5' } -TimeoutSec 45 | Out-Null
        } catch {
            $script:downloadFallbacks++
            Log "image IWR fallback -> curl :: $($_.Exception.Message)"
            & curl.exe -L --fail --silent --show-error --connect-timeout 15 --max-time 60 `
                -A $ua -H 'Accept: image/png,image/jpeg,image/bmp,image/*;q=0.5' -o $tmp $Url
            if ($LASTEXITCODE -ne 0) { throw "curl.exe image download failed with exit code $LASTEXITCODE" }
        }

        if (!(Test-Path -LiteralPath $tmp) -or (Get-Item -LiteralPath $tmp).Length -lt 200) {
            throw "Downloaded asset is empty: $Url"
        }

        $kind = Get-ImageKind $tmp
        if (!$kind) { throw 'Downloaded response is not a supported image (possible HTML/error response).' }
        if ($kind -eq 'webp') { throw 'Downloaded image is WebP; original PNG/JPEG source is required for GDI+.' }

        Remove-OldImageVariants $BasePath
        $target = $BasePath + '.' + $kind
        Move-Item -LiteralPath $tmp -Destination $target -Force
        return $target
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
        foreach ($img in @($pageObj.images)) { if ($img.title) { $titles += [string]$img.title } }
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

function Write-Status([string]$LastError='') {
    $safeError = ($LastError -replace '[\r\n]+',' ') -replace '=','-'
    $text = "[Sync]`r`nTowers=$towerOK`r`nMaps=$mapOK`r`nMisses=$misses`r`nErrors=$errors`r`nApiFallbacks=$apiFallbacks`r`nDownloadFallbacks=$downloadFallbacks`r`nLastError=$safeError`r`nCompleted=$(Get-Date -Format o)`r`n"
    [IO.File]::WriteAllText($statusPath, $text, (New-Object Text.UTF8Encoding($false)))
}

$lastError = ''
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
            $target = Download-Image $url (Join-Path $towerDir $key)
            $towerOK++
            Log "tower OK $display -> $target"
        } else {
            $misses++
            Log "tower MISS $display (no suitable default portrait)"
        }
    } catch {
        $errors++
        $lastError = "tower $display :: $($_.Exception.Message)"
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
        $primary = Get-PagePrimaryFile ('Map:' + $page)
        if ($primary) { $url = Get-ImageOriginalUrl $primary }

        if (!$url) {
            $titles = @(Get-PageImages $page)
            $file = Choose-TopDown $display $titles
            if (!$file) {
                $titles = @(Get-PageImages ('Map:' + $page))
                $file = Choose-TopDown $display $titles
            }
            if ($file) { $url = Get-ImageOriginalUrl $file }
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
        $lastError = "map $display :: $($_.Exception.Message)"
        Log "map ERROR $display :: $($_.Exception.Message)"
    }
}

Write-Status $lastError
$markerName = if (![string]::IsNullOrWhiteSpace($MapName)) { 'asset-sync-' + (Safe-Key $MapName) + '.done' } else { 'asset-sync-catalog.done' }
[IO.File]::WriteAllText((Join-Path $root $markerName), (Get-Date -Format 'o'), (New-Object Text.UTF8Encoding($false)))
Log "asset sync complete towers=$towerOK maps=$mapOK misses=$misses errors=$errors apiFallbacks=$apiFallbacks downloadFallbacks=$downloadFallbacks"
exit 0
