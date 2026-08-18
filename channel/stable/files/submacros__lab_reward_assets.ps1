param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [string]$Names = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$wikiRoot = 'https://tds.fandom.com'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 StrategyLabRewards/0.3.8'
$root = Join-Path $env:APPDATA 'Ultimate_Macro\StrategyEditor'
$rewardDir = Join-Path $root 'RewardLibrary'
$catalogPath = Join-Path $InstallDir 'Resources\StrategyLab\Rewards\catalog.ini'
$logPath = Join-Path $root 'reward-assets.log'
$statusPath = Join-Path $root 'reward-assets-status.ini'
New-Item -ItemType Directory -Force -Path $rewardDir | Out-Null

$ok = 0
$misses = 0
$errors = 0
$optimized = 0

function Log([string]$Text) {
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text)
}

function Safe-Key([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return (($Value.Trim().ToLowerInvariant() -replace '[^a-z0-9]+','-').Trim('-'))
}

function Flat([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return (($Value -replace '[^A-Za-z0-9]','').ToLowerInvariant())
}

function Read-Ini([string]$Path) {
    $result = [ordered]@{}
    $section = $null
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if (!$line -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }
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

function Get-Value($Entry,[string]$Key,[string]$Default='') {
    if ($Entry -and $Entry.Contains($Key)) { return [string]$Entry[$Key] }
    return $Default
}

function Write-Status([string]$LastError='') {
    $safe = ($LastError -replace '[\r\n]+',' ') -replace '=','-'
    $text = "[Sync]`r`nRewards=$ok`r`nMisses=$misses`r`nErrors=$errors`r`nOptimized=$optimized`r`nLastError=$safe`r`nCompleted=$(Get-Date -Format o)`r`n"
    [IO.File]::WriteAllText($statusPath,$text,(New-Object Text.UTF8Encoding($false)))
}

if (!(Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    Log "catalog missing: $catalogPath"
    Write-Status 'Reward catalog is missing.'
    exit 0
}

$catalog = Read-Ini $catalogPath
$aliasIndex = @{}
foreach ($section in $catalog.Keys) {
    $entry = $catalog[$section]
    $aliasIndex[(Safe-Key $section)] = $section
    $display = Get-Value $entry 'display' $section
    $aliasIndex[(Safe-Key $display)] = $section
    foreach ($alias in (Get-Value $entry 'aliases' $section).Split('|')) {
        $key = Safe-Key $alias
        if ($key) { $aliasIndex[$key] = $section }
    }
}

$wanted = New-Object System.Collections.Generic.List[string]
if ([string]::IsNullOrWhiteSpace($Names)) {
    foreach ($section in $catalog.Keys) {
        if ((Get-Value $catalog[$section] 'core' '0') -eq '1') { $wanted.Add([string]$section) }
    }
} else {
    foreach ($rawName in $Names.Split('|')) {
        $key = Safe-Key $rawName
        if ($key -and $aliasIndex.ContainsKey($key)) {
            $section = [string]$aliasIndex[$key]
            if (!$wanted.Contains($section)) { $wanted.Add($section) }
        }
    }
}

if ($wanted.Count -eq 0) {
    Log 'sync SKIP: no recognized reward names'
    Write-Status 'No recognized reward names.'
    exit 0
}

function Common-Headers([string]$Accept) {
    return @{
        'User-Agent'=$ua
        'Accept'=$Accept
        'Accept-Language'='en-US,en;q=0.9'
        'Referer'="$wikiRoot/"
        'Cache-Control'='no-cache'
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

function Invoke-Wiki([hashtable]$Params) {
    $uri = Build-WikiUri $Params
    try {
        return Invoke-RestMethod -Uri $uri -Headers (Common-Headers 'application/json') -TimeoutSec 25
    } catch {
        $tmp = Join-Path $env:TEMP ('strategy-lab-reward-' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            & curl.exe -L --fail --silent --show-error --compressed --connect-timeout 15 --max-time 45 `
                -A $ua -e "$wikiRoot/" -H 'Accept: application/json' -o $tmp $uri
            if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $tmp)) { throw "curl exit $LASTEXITCODE" }
            return ([IO.File]::ReadAllText($tmp) | ConvertFrom-Json)
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Normalize-FileTitle([string]$Title) {
    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
    if ($Title.StartsWith('File:')) { return $Title }
    return 'File:' + $Title
}

function Get-PagePrimaryFile([string]$Page) {
    $json = Invoke-Wiki @{action='query';titles=$Page;prop='pageimages';piprop='name'}
    foreach ($pageObj in $json.query.pages.PSObject.Properties.Value) {
        if ($pageObj.pageimage) { return Normalize-FileTitle ([string]$pageObj.pageimage) }
    }
    return $null
}

function Get-PageImages([string]$Page) {
    $json = Invoke-Wiki @{action='query';titles=$Page;prop='images';imlimit='max'}
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
    $json = Invoke-Wiki @{action='query';titles=$fileTitle;prop='imageinfo';iiprop='url'}
    foreach ($pageObj in $json.query.pages.PSObject.Properties.Value) {
        $ii = @($pageObj.imageinfo)
        if ($ii.Count -gt 0 -and $ii[0].url) {
            $url = [string]$ii[0].url
            if ($url -match '(?i)([?&])format=[^&]*') {
                return [regex]::Replace($url,'(?i)([?&])format=[^&]*','${1}format=original')
            }
            return $url + ($(if ($url.Contains('?')) {'&'} else {'?'})) + 'format=original'
        }
    }
    return $null
}

function Choose-RewardImage([string]$Section,$Entry) {
    $page = Get-Value $Entry 'wikiPage' $Section
    $display = Get-Value $Entry 'display' $Section
    $hints = @(Get-Value $Entry 'hints' $Section -split '\|')
    $primary = Get-PagePrimaryFile $page
    $candidates = @()
    if ($primary) { $candidates += $primary }
    $candidates += @(Get-PageImages $page)
    $candidates = @($candidates | Select-Object -Unique)
    if ($candidates.Count -eq 0) { return $null }

    $ranked = foreach ($title in $candidates) {
        $file = $title -replace '^File:',''
        $flat = Flat $file
        $score = 0
        if ($primary -and $title -eq $primary) { $score += 24 }
        if ($flat.Contains((Flat $display))) { $score += 55 }
        if ($flat.Contains((Flat $Section))) { $score += 45 }
        foreach ($hint in $hints) {
            $hf = Flat $hint
            if ($hf -and $flat.Contains($hf)) { $score += 70 }
        }
        if ($flat.Contains('icon')) { $score += 22 }
        if ($flat.Contains('item')) { $score += 8 }
        if ($flat -match 'logo|banner|background|bg|map|tower|skin|emote|nav|button|gui') { $score -= 90 }
        [PSCustomObject]@{Title=$title;Score=$score}
    }
    return ($ranked | Sort-Object Score -Descending | Select-Object -First 1).Title
}

function Get-ImageKind([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) { return $null }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 8 -and $bytes[0]-eq 0x89 -and $bytes[1]-eq 0x50 -and $bytes[2]-eq 0x4E -and $bytes[3]-eq 0x47) { return 'png' }
    if ($bytes.Length -ge 3 -and $bytes[0]-eq 0xFF -and $bytes[1]-eq 0xD8 -and $bytes[2]-eq 0xFF) { return 'jpg' }
    if ($bytes.Length -ge 2 -and $bytes[0]-eq 0x42 -and $bytes[1]-eq 0x4D) { return 'bmp' }
    if ($bytes.Length -ge 12 -and $bytes[0]-eq 0x52 -and $bytes[1]-eq 0x49 -and $bytes[2]-eq 0x46 -and $bytes[3]-eq 0x46 -and $bytes[8]-eq 0x57 -and $bytes[9]-eq 0x45 -and $bytes[10]-eq 0x42 -and $bytes[11]-eq 0x50) { return 'webp' }
    return $null
}

function Download-Original([string]$Url,[string]$Target) {
    $accept = 'image/png,image/jpeg,image/bmp,image/*;q=0.7,*/*;q=0.1'
    Remove-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Target -Headers (Common-Headers $accept) -TimeoutSec 45 | Out-Null
    } catch {
        & curl.exe -L --fail --silent --show-error --compressed --connect-timeout 15 --max-time 60 `
            -A $ua -e "$wikiRoot/" -H "Accept: $accept" -o $Target $Url
        if ($LASTEXITCODE -ne 0) { throw "curl image exit $LASTEXITCODE" }
    }
}

function Save-Jpeg($Bitmap,[string]$Path,[int]$Quality) {
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object {$_.MimeType -eq 'image/jpeg'} | Select-Object -First 1
    $parameters = [System.Drawing.Imaging.EncoderParameters]::new(1)
    $parameters.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new([System.Drawing.Imaging.Encoder]::Quality,[long]$Quality)
    try { $Bitmap.Save($Path,$codec,$parameters) } finally { $parameters.Dispose() }
}

function Optimize-Reward([string]$Input,[string]$Target) {
    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Image]::FromFile($Input)
    $canvas = $null
    $graphics = $null
    try {
        $size = 112
        $padding = 8
        $usable = $size - ($padding * 2)
        $scale = [Math]::Min($usable / [double]$image.Width,$usable / [double]$image.Height)
        $w = [Math]::Max(1,[int][Math]::Round($image.Width * $scale))
        $h = [Math]::Max(1,[int][Math]::Round($image.Height * $scale))
        $x = [int][Math]::Floor(($size-$w)/2)
        $y = [int][Math]::Floor(($size-$h)/2)
        $canvas = [System.Drawing.Bitmap]::new($size,$size)
        $graphics = [System.Drawing.Graphics]::FromImage($canvas)
        $graphics.Clear([System.Drawing.Color]::FromArgb(21,25,31))
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.DrawImage($image,$x,$y,$w,$h)
        Save-Jpeg $canvas $Target 86
        $script:optimized++
    } finally {
        if ($graphics) {$graphics.Dispose()}
        if ($canvas) {$canvas.Dispose()}
        if ($image) {$image.Dispose()}
    }
}

foreach ($section in $wanted) {
    $entry = $catalog[$section]
    $key = Safe-Key $section
    $target = Join-Path $rewardDir ($key + '.jpg')
    try {
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            if ((Get-Item -LiteralPath $target).Length -gt 500) {
                $ok++
                continue
            }
        }

        $fileTitle = Choose-RewardImage $section $entry
        if (!$fileTitle) {
            $misses++
            Log "MISS $section :: no usable page image"
            continue
        }
        $url = Get-ImageOriginalUrl $fileTitle
        if (!$url) {
            $misses++
            Log "MISS $section :: image URL missing for $fileTitle"
            continue
        }

        $tmp = Join-Path $env:TEMP ('strategy-lab-reward-image-' + [guid]::NewGuid().ToString('N'))
        try {
            Download-Original $url $tmp
            $kind = Get-ImageKind $tmp
            if (!$kind -or $kind -eq 'webp') {
                $misses++
                Log "MISS $section :: unsupported response $kind :: $fileTitle"
                continue
            }
            Optimize-Reward $tmp $target
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                $ok++
                Log "OK $section <- $fileTitle -> $target"
            } else {
                throw 'optimized target was not created'
            }
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    } catch {
        $errors++
        Log "ERROR $section :: $($_.Exception.Message)"
    }
}

Write-Status
exit 0
