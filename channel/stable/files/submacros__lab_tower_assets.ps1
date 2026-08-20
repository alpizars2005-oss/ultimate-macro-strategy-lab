param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [Parameter(Mandatory=$true)][string]$TowerNames
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$wikiRoot = 'https://tds.fandom.com'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36 UltimateMacroStrategyLab/0.4.3'
$root = Join-Path $env:APPDATA 'Ultimate_Macro\StrategyEditor'
$towerDir = Join-Path $root 'TowerLibrary'
$previewDir = Join-Path $towerDir 'preview'
$logPath = Join-Path $root 'tower-asset-sync.log'
$statusPath = Join-Path $root 'tower-asset-status.ini'
New-Item -ItemType Directory -Force -Path $root,$towerDir,$previewDir | Out-Null

$towerOK = 0
$misses = 0
$errors = 0
$optimized = 0
$lastError = ''

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
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $result }
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
    $tmp = Join-Path $env:TEMP ('strategy-lab-wiki-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & curl.exe -L --fail --silent --show-error --compressed --connect-timeout 12 --max-time 35 `
            -A $ua -e "$wikiRoot/" -H 'Accept: application/json' -o $tmp $Url
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
        return Invoke-RestMethod -Uri $uri -Headers (Common-Headers 'application/json') -TimeoutSec 20
    } catch {
        Log ("API REST fallback -> curl :: " + $_.Exception.Message)
        $text = Invoke-CurlText $uri
        if ([string]::IsNullOrWhiteSpace($text)) { throw 'Fandom API returned an empty response.' }
        return ($text | ConvertFrom-Json)
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
        if ($ii.Count -gt 0 -and $ii[0].url) {
            $url = [string]$ii[0].url
            # Fandom CDN may content-negotiate WebP. Asking for the original format is
            # important because the bundled GDI+ path is intentionally PNG/JPEG/BMP only.
            if ($url.Contains('?')) { return $url + '&format=original' }
            return $url + '?format=original'
        }
    }
    return $null
}

function Choose-PreferredTowerImage([string]$TowerName,[string[]]$Titles) {
    $normTower = ($TowerName -replace '[^A-Za-z0-9]','').ToLowerInvariant()
    $ranked = foreach ($title in $Titles) {
        $name = $title -replace '^File:',''
        $flat = ($name -replace '[^A-Za-z0-9]','').ToLowerInvariant()
        $score = 0

        # Primary contract discovered from the current in-game gallery assets:
        # prefer the no-skin default icon exported from the game (Default + IconIG).
        if ($name -match '(?i)default' -and $name -match '(?i)iconig') { $score += 600 }
        elseif ($name -match '(?i)default') { $score += 150 }

        # Prefer lossless source assets when several candidates share the same family.
        if ($name -match '(?i)\.png$') { $score += 45 }
        elseif ($name -match '(?i)\.jpe?g$') { $score += 20 }
        elseif ($name -match '(?i)\.bmp$') { $score += 5 }

        # Useful fallbacks when a tower has no IconIG asset.
        if ($name -match '(?i)render|portrait|static|dynamic') { $score += 70 }
        if ($flat.Contains($normTower)) { $score += 35 }

        # Strongly reject old/skin/unrelated assets even when they contain "Default".
        if ($name -match '(?i)old|legacy|classic|unused|outdated|deprecated|beta') { $score -= 350 }
        if ($name -match '(?i)golden|skin|crate|halloween|christmas|valentine|toy|plushie|neko|vigilante|slayer|bunny|ducky|pirate|galactic|prime|mage') { $score -= 260 }
        if ($name -match '(?i)weapon|gun|sound|voice|theme|ost|ogg|gif|emoji|badge|banner|face|concept|upgrade|level[1-9]') { $score -= 220 }

        [PSCustomObject]@{Title=$title; Name=$name; Score=$score}
    }

    $bestIconIG = $ranked |
        Where-Object { $_.Name -match '(?i)default' -and $_.Name -match '(?i)iconig' -and $_.Score -gt 0 } |
        Sort-Object Score -Descending |
        Select-Object -First 1
    if ($bestIconIG) { return [string]$bestIconIG.Title }

    $bestDefault = $ranked |
        Where-Object { $_.Name -match '(?i)default' -and $_.Score -ge 100 } |
        Sort-Object Score -Descending |
        Select-Object -First 1
    if ($bestDefault) { return [string]$bestDefault.Title }

    $bestAny = $ranked | Sort-Object Score -Descending | Select-Object -First 1
    if ($bestAny -and $bestAny.Score -ge 70) { return [string]$bestAny.Title }
    return $null
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

function Remove-TowerVariants([string]$BasePath) {
    foreach ($ext in @('.png','.jpg','.jpeg','.bmp','.webp')) {
        Remove-Item -LiteralPath ($BasePath + $ext) -Force -ErrorAction SilentlyContinue
    }
}

function Save-Png([System.Drawing.Bitmap]$Bitmap,[string]$Path) {
    $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function Optimize-Tower([string]$InputPath,[string]$BasePath) {
    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Image]::FromFile($InputPath)
    $bitmap = $null
    $graphics = $null
    $temp = $BasePath + '.tmp.png'
    try {
        $canvas = 256
        $padding = 10
        $usable = $canvas - (2 * $padding)
        $scale = [Math]::Min($usable / [double]$image.Width, $usable / [double]$image.Height)
        $drawW = [Math]::Max(1, [int][Math]::Round($image.Width * $scale))
        $drawH = [Math]::Max(1, [int][Math]::Round($image.Height * $scale))
        $drawX = [int][Math]::Floor(($canvas - $drawW) / 2)
        $drawY = [int][Math]::Floor(($canvas - $drawH) / 2)

        $bitmap = [System.Drawing.Bitmap]::new($canvas, $canvas)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($image, $drawX, $drawY, $drawW, $drawH)

        $target = $BasePath + '.png'
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        Save-Png $bitmap $temp
        if (!(Test-Path -LiteralPath $temp) -or (Get-Item -LiteralPath $temp).Length -lt 200) {
            throw 'Optimized PNG portrait was not written correctly.'
        }
        Remove-TowerVariants $BasePath
        Move-Item -LiteralPath $temp -Destination $target -Force
        $script:optimized++
        return $target
    } finally {
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
        if ($image) { $image.Dispose() }
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

function Download-Tower([string]$Url,[string]$BasePath) {
    $tmp = $BasePath + '.download'
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    try {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp `
                -Headers (Common-Headers 'image/png,image/jpeg,image/bmp,image/*;q=0.5') -TimeoutSec 35 | Out-Null
        } catch {
            Log ("image IWR fallback -> curl :: " + $_.Exception.Message)
            & curl.exe -L --fail --silent --show-error --compressed --connect-timeout 12 --max-time 45 `
                -A $ua -e "$wikiRoot/" -H 'Accept: image/png,image/jpeg,image/bmp,image/*;q=0.5' -o $tmp $Url
            if ($LASTEXITCODE -ne 0) { throw "curl.exe image download failed with exit code $LASTEXITCODE" }
        }

        if (!(Test-Path -LiteralPath $tmp) -or (Get-Item -LiteralPath $tmp).Length -lt 200) {
            throw 'Downloaded portrait is empty.'
        }
        $kind = Get-ImageKind $tmp

        # Fandom can return WebP through content negotiation even when the MediaWiki
        # imageinfo URL ends in PNG/JPEG and already contains format=original. If IWR
        # accepted that response, retry once through curl while explicitly advertising
        # only the formats supported by the bundled GDI+ path.
        if ($kind -eq 'webp') {
            Log ("image WEBP retry -> curl original :: " + $Url)
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            & curl.exe -L --fail --silent --show-error --compressed --connect-timeout 12 --max-time 45 `
                -A $ua -e "$wikiRoot/" `
                -H 'Accept: image/png,image/jpeg,image/bmp,*/*;q=0.1' `
                -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' `
                -o $tmp $Url
            if ($LASTEXITCODE -ne 0) {
                throw "curl.exe original-image retry failed with exit code $LASTEXITCODE"
            }
            if (!(Test-Path -LiteralPath $tmp) -or (Get-Item -LiteralPath $tmp).Length -lt 200) {
                throw 'Original-image retry returned an empty portrait.'
            }
            $kind = Get-ImageKind $tmp
        }

        if (!$kind) { throw 'Downloaded response is not an image.' }
        if ($kind -eq 'webp') {
            throw 'Fandom still returned WebP after the explicit original-image retry.'
        }

        try {
            return Optimize-Tower $tmp $BasePath
        } catch {
            # Never discard a valid image solely because System.Drawing optimization failed.
            Log ("optimization fallback :: " + $_.Exception.Message)
            Remove-TowerVariants $BasePath
            $target = $BasePath + '.' + $kind
            Move-Item -LiteralPath $tmp -Destination $target -Force
            return $target
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Write-Status {
    $safeError = ($script:lastError -replace '[\r\n]+',' ') -replace '=','-'
    $text = "[Sync]`r`nTowers=$script:towerOK`r`nMisses=$script:misses`r`nErrors=$script:errors`r`nOptimized=$script:optimized`r`nLastError=$safeError`r`nCompleted=$(Get-Date -Format o)`r`n"
    [IO.File]::WriteAllText($statusPath, $text, (New-Object Text.UTF8Encoding($false)))
}

try {
    $InstallDir = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallDir.Trim()).Trim('"'))
    $installedCatalogPath = Join-Path $InstallDir 'Resources\StrategyLab\Towers\catalog.ini'
    $repoCatalogPath = Join-Path $PSScriptRoot 'Resources__StrategyLab__Towers__catalog.ini'
    $catalogPath = $null

    if (Test-Path -LiteralPath $installedCatalogPath -PathType Leaf) {
        $catalogPath = $installedCatalogPath
        Log "catalog INSTALLED -> $catalogPath"
    } elseif (Test-Path -LiteralPath $repoCatalogPath -PathType Leaf) {
        $catalogPath = $repoCatalogPath
        Log "catalog REPO -> $catalogPath"
    } else {
        throw "Tower catalog not found. Checked installed path '$installedCatalogPath' and repo path '$repoCatalogPath'."
    }

    $catalog = Read-Ini $catalogPath
    if ($catalog.Count -le 0) {
        throw "Tower catalog is empty: $catalogPath"
    }
    Log "catalog READY towers=$($catalog.Count)"

    if ([string]::IsNullOrWhiteSpace($TowerNames) -or $TowerNames.Trim() -eq '*') {
        $requested = @($catalog.Keys)
        Log "tower SYNC ALL count=$($requested.Count)"
    } else {
        $requested = @($TowerNames.Split('|') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
        Log "tower SYNC SELECTED count=$($requested.Count)"
    }
    if ($requested.Count -le 0) {
        throw 'Tower request resolved to zero entries.'
    }

    foreach ($requestedName in $requested) {
        $section = $null
        foreach ($candidate in $catalog.Keys) {
            $aliases = if ($catalog[$candidate].Contains('aliases')) { @($catalog[$candidate]['aliases'].Split('|')) } else { @($candidate) }
            $display = if ($catalog[$candidate].Contains('display')) { $catalog[$candidate]['display'] } else { $candidate }
            if ($display -ieq $requestedName -or $candidate -ieq $requestedName -or ($aliases | Where-Object { $_ -ieq $requestedName })) {
                $section = $candidate
                break
            }
        }
        if (!$section) { $section = $requestedName }

        $info = if ($catalog.Contains($section)) { $catalog[$section] } else { $null }
        $display = if ($info -and $info.Contains('display')) { $info['display'] } else { $requestedName }
        $page = if ($info -and $info.Contains('wikiPage')) { $info['wikiPage'] } else { $display }
        $key = Safe-Key $section
        $base = Join-Path $towerDir $key

        # A valid local portrait is immutable until the user explicitly clears/re-syncs it.
        $existing = $null
        foreach ($ext in @('.png','.jpg','.jpeg','.bmp')) {
            $candidate = $base + $ext
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $existing = $candidate; break }
        }
        if ($existing) {
            $towerOK++
            Log "tower CACHE $display -> $existing"
            continue
        }

        try {
            $url = $null
            $galleryTitles = @(Get-PageImages ($page + '/Gallery'))
            $preferredFile = Choose-PreferredTowerImage $display $galleryTitles
            if ($preferredFile) {
                $url = Get-ImageOriginalUrl $preferredFile
                if ($url) {
                    $label = if (($preferredFile -match '(?i)default') -and ($preferredFile -match '(?i)iconig')) { 'ICONIG' } else { 'PREFERRED' }
                    Log "tower $label $display [$preferredFile]"
                }
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
                $target = Download-Tower $url $base
                $towerOK++
                Log "tower OK $display -> $target"
            } else {
                $misses++
                Log "tower MISS $display (no suitable portrait found)"
            }
        } catch {
            $errors++
            $lastError = "tower $display :: $($_.Exception.Message)"
            Log "tower ERROR $display :: $($_.Exception.Message)"
        }
    }
} catch {
    $errors++
    $lastError = $_.Exception.Message
    Log ("worker ERROR :: " + $_.Exception.Message)
} finally {
    Write-Status
}

exit 0
