param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [string]$MapName = '',
    [string]$TowerNames = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ua = 'UltimateMacroStrategyLab/0.2 (private development; TDS Wiki asset cache)'
$root = Join-Path $env:APPDATA 'Ultimate_Macro\StrategyEditor'
$towerDir = Join-Path $root 'TowerLibrary'
$mapDir = Join-Path $root 'MapLibrary\reference'
New-Item -ItemType Directory -Force -Path $towerDir,$mapDir | Out-Null
$logPath = Join-Path $root 'asset-sync.log'

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

function Download-Url([string]$Url,[string]$Target) {
    $tmp = $Target + '.download'
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri $Url -OutFile $tmp -Headers @{ 'User-Agent'=$ua } -TimeoutSec 45
    if (!(Test-Path -LiteralPath $tmp) -or (Get-Item -LiteralPath $tmp).Length -lt 200) {
        throw "Downloaded asset is empty: $Url"
    }
    Move-Item -LiteralPath $tmp -Destination $Target -Force
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

function Choose-TopDown([string]$MapName,[string[]]$Titles) {
    $norm = ($MapName -replace '[^A-Za-z0-9]','').ToLowerInvariant()
    $ranked = foreach ($title in $Titles) {
        $name = $title -replace '^File:',''
        $flat = ($name -replace '[^A-Za-z0-9]','').ToLowerInvariant()
        $score = 0
        if ($name -match '(?i)top[ _-]*down|topdown|overhead|bird.?s.?eye') { $score += 100 }
        if ($flat.Contains($norm) -or $norm.Contains(($flat -replace '(topdown|overhead)',''))) { $score += 25 }
        if ($name -match '(?i)icon|logo|thumbnail') { $score -= 50 }
        [PSCustomObject]@{Title=$title; Score=$score}
    }
    $best = $ranked | Sort-Object Score -Descending | Select-Object -First 1
    if ($best -and $best.Score -ge 100) { return [string]$best.Title }
    return $null
}

$towerCatalog = Read-Ini (Join-Path $InstallDir 'Resources\StrategyLab\Towers\catalog.ini')
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
        $url = Get-PageThumbnail $page 128
        if ($url) {
            $target = Join-Path $towerDir ($key + '.png')
            Download-Url $url $target
            Log "tower OK $display -> $target"
        } else { Log "tower MISS $display (no page thumbnail)" }
    } catch { Log "tower ERROR $display :: $($_.Exception.Message)" }
}

$mapCatalog = Read-Ini (Join-Path $InstallDir 'Resources\StrategyLab\Maps\catalog.ini')
$mapSections = if (![string]::IsNullOrWhiteSpace($MapName)) { @($MapName.Trim()) } else { @($mapCatalog.Keys) }
foreach ($section in $mapSections) {
    $info = if ($mapCatalog.Contains($section)) { $mapCatalog[$section] } else { $null }
    $display = if ($info -and $info.Contains('display')) { $info['display'] } else { $section }
    $page = if ($info -and $info.Contains('wikiPage')) { $info['wikiPage'] } else { $display }
    $key = Safe-Key $section
    try {
        $titles = @(Get-PageImages $page)
        $file = Choose-TopDown $display $titles
        if (!$file) {
            $titles = @(Get-PageImages ('Map:' + $page))
            $file = Choose-TopDown $display $titles
        }
        if ($file) {
            $url = Get-ImageThumbnail $file 1280
            if ($url) {
                $target = Join-Path $mapDir ($key + '.png')
                Download-Url $url $target
                Log "map OK $display [$file] -> $target"
            } else { Log "map MISS $display (no image URL for $file)" }
        } else { Log "map MISS $display (no Top Down image discovered)" }
    } catch { Log "map ERROR $display :: $($_.Exception.Message)" }
}

$markerName = if (![string]::IsNullOrWhiteSpace($MapName)) { 'asset-sync-' + (Safe-Key $MapName) + '.done' } else { 'asset-sync-catalog.done' }
[IO.File]::WriteAllText((Join-Path $root $markerName), (Get-Date -Format 'o'), (New-Object Text.UTF8Encoding($false)))
Log 'asset sync complete'
exit 0
