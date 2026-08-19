param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [Parameter(Mandatory=$true)][string]$Screenshot,
    [Parameter(Mandatory=$true)][string]$StrategyPath,
    [Parameter(Mandatory=$true)][string]$MapName,
    [string]$Result = ''
)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:APPDATA 'Ultimate_Macro\StrategyEditor'
$logPath = Join-Path $root 'postrun-calibration.log'
$calibrationDir = Join-Path $root 'MapLibrary\calibration'
New-Item -ItemType Directory -Force -Path $calibrationDir | Out-Null

function Log([string]$Text) {
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text)
}

function Safe-Key([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return (($Value.Trim().ToLowerInvariant() -replace '[^a-z0-9]+','-').Trim('-'))
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

function Ini-Value($Ini,[string]$Section,[string]$Key,[string]$Default='') {
    if ($Ini.Contains($Section) -and $Ini[$Section].Contains($Key)) { return [string]$Ini[$Section][$Key] }
    return $Default
}

function Median([double[]]$Values) {
    if (!$Values -or $Values.Count -eq 0) { return [double]::NaN }
    $v = @($Values | Sort-Object)
    $n = $v.Count
    if (($n % 2) -eq 1) { return [double]$v[[int]($n/2)] }
    return ([double]$v[$n/2-1] + [double]$v[$n/2]) / 2.0
}

try {
    $InstallDir = [IO.Path]::GetFullPath($InstallDir.Trim().Trim('"'))
    $Screenshot = [IO.Path]::GetFullPath($Screenshot.Trim().Trim('"'))
    $StrategyPath = [IO.Path]::GetFullPath($StrategyPath.Trim().Trim('"'))
    if (!(Test-Path -LiteralPath $Screenshot -PathType Leaf)) { throw "Screenshot missing: $Screenshot" }
    if (!(Test-Path -LiteralPath $StrategyPath -PathType Leaf)) { throw "Strategy missing: $StrategyPath" }

    $towerCatalogPath = Join-Path $InstallDir 'Resources\StrategyLab\Towers\catalog.ini'
    if (!(Test-Path -LiteralPath $towerCatalogPath -PathType Leaf)) { throw 'Tower catalog is missing.' }

    $strategy = Read-Ini $StrategyPath
    $catalog = Read-Ini $towerCatalogPath
    $requiredText = Ini-Value $strategy 'Settings' 'requiredTowers' ''
    $required = @($requiredText.Split(',') | ForEach-Object {$_.Trim()} | Where-Object {$_})
    if ($required.Count -eq 0) { throw 'Strategy has no requiredTowers.' }

    $strategyW = 1920.0
    $strategyH = 1009.0
    $wText = Ini-Value $strategy 'DO NOT EDIT' 'width' '1920'
    $hText = Ini-Value $strategy 'DO NOT EDIT' 'height' '1009'
    if ($wText -as [double]) { $strategyW = [double]$wText }
    if ($hText -as [double]) { $strategyH = [double]$hText }
    if ($strategyW -lt 100 -or $strategyH -lt 100) { throw 'Strategy dimensions are not usable.' }

    $aliasIndex = @{}
    foreach ($section in $catalog.Keys) {
        $entry = $catalog[$section]
        $aliasIndex[(Safe-Key $section)] = $section
        $display = if ($entry.Contains('display')) {[string]$entry['display']} else {$section}
        $aliasIndex[(Safe-Key $display)] = $section
        $aliases = if ($entry.Contains('aliases')) {[string]$entry['aliases']} else {$section}
        foreach ($alias in $aliases.Split('|')) {
            $k = Safe-Key $alias
            if ($k) { $aliasIndex[$k] = $section }
        }
    }

    $footprints = @{}
    foreach ($slot in 1..$required.Count) {
        $name = $required[$slot-1]
        $k = Safe-Key $name
        $section = if ($aliasIndex.ContainsKey($k)) {[string]$aliasIndex[$k]} else {$null}
        $fp = 1.5
        if ($section) {
            $value = if ($catalog[$section].Contains('placementFootprint')) {[string]$catalog[$section]['placementFootprint']} else {'1.5'}
            if ($value -as [double]) { $fp = [double]$value }
        }
        $footprints[$slot] = [Math]::Max(0.5,[Math]::Min(4.0,$fp))
    }

    $placements = New-Object System.Collections.Generic.List[object]
    foreach ($raw in Get-Content -LiteralPath $StrategyPath) {
        if ($raw -match '(?i)^\s*SpawnTower\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(\d+)\s*,\s*([^\)]+)\)') {
            $slot = [int]$Matches[3]
            if (!$footprints.ContainsKey($slot)) { continue }
            $placements.Add([PSCustomObject]@{
                X=[double]$Matches[1]; Y=[double]$Matches[2]; Slot=$slot; Footprint=[double]$footprints[$slot]
            })
        }
    }
    if ($placements.Count -eq 0) { throw 'No SpawnTower placements were found.' }

    Add-Type -AssemblyName System.Drawing
    $src = [System.Drawing.Bitmap]::FromFile($Screenshot)
    $bmp = $null
    $data = $null
    try {
        # Force predictable 32-bit BGRA bytes for fast cyan sampling.
        $bmp = [System.Drawing.Bitmap]::new($src.Width,$src.Height,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try { $g.DrawImage($src,0,0,$src.Width,$src.Height) } finally { $g.Dispose() }

        $rect = [System.Drawing.Rectangle]::new(0,0,$bmp.Width,$bmp.Height)
        $data = $bmp.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $strideAbs = [Math]::Abs($data.Stride)
        $bytes = New-Object byte[] ($strideAbs * $bmp.Height)
        [Runtime.InteropServices.Marshal]::Copy($data.Scan0,$bytes,0,$bytes.Length)

        function Is-Cyan([int]$x,[int]$y) {
            if ($x -lt 0 -or $y -lt 0 -or $x -ge $bmp.Width -or $y -ge $bmp.Height) { return $false }
            $row = if ($data.Stride -ge 0) {$y} else {$bmp.Height - 1 - $y}
            $i = $row * $strideAbs + $x * 4
            $b = [int]$bytes[$i]
            $gch = [int]$bytes[$i+1]
            $r = [int]$bytes[$i+2]
            # TDS placement outlines in supplied references are around RGB 0,220,250.
            return ($r -le 100 -and $gch -ge 145 -and $b -ge 185 -and ($b-$r) -ge 105 -and ($gch-$r) -ge 80)
        }

        $scaleX = $bmp.Width / $strategyW
        $scaleY = $bmp.Height / $strategyH
        $priorPPU = 26.0
        $playableBottom = $strategyH * (918.0/1009.0)
        $samples = New-Object System.Collections.Generic.List[object]

        foreach ($p in $placements) {
            if ($p.Y -gt $playableBottom) { continue }
            $cx0 = [double]$p.X * $scaleX
            $cy0 = [double]$p.Y * $scaleY
            $expectedR = [double]$p.Footprint * $priorPPU * $scaleX
            if ($expectedR -lt 10 -or $expectedR -gt 120) { continue }

            $reach = [int][Math]::Ceiling($expectedR + 16)
            $x0 = [Math]::Max(0,[int][Math]::Floor($cx0-$reach))
            $x1 = [Math]::Min($bmp.Width-1,[int][Math]::Ceiling($cx0+$reach))
            $y0 = [Math]::Max(0,[int][Math]::Floor($cy0-$reach))
            $y1 = [Math]::Min($bmp.Height-1,[int][Math]::Ceiling($cy0+$reach))
            $cyan = New-Object System.Collections.Generic.List[object]
            for ($yy=$y0; $yy -le $y1; $yy++) {
                for ($xx=$x0; $xx -le $x1; $xx++) {
                    if (Is-Cyan $xx $yy) { $cyan.Add([PSCustomObject]@{X=$xx;Y=$yy}) }
                }
            }
            if ($cyan.Count -lt 10) { continue }

            $bestScore = 0
            $bestDx = 0
            $bestDy = 0
            foreach ($dy in -10,-8,-6,-4,-2,0,2,4,6,8,10) {
                foreach ($dx in -10,-8,-6,-4,-2,0,2,4,6,8,10) {
                    $score = 0
                    $cx = $cx0 + $dx
                    $cy = $cy0 + $dy
                    foreach ($q in $cyan) {
                        $rx = $q.X-$cx; $ry=$q.Y-$cy
                        $d = [Math]::Sqrt($rx*$rx+$ry*$ry)
                        if ([Math]::Abs($d-$expectedR) -le 3.5) { $score++ }
                    }
                    if ($score -gt $bestScore) {
                        $bestScore=$score; $bestDx=$dx; $bestDy=$dy
                    }
                }
            }
            if ($bestScore -lt 12) { continue }

            $cxBest = $cx0+$bestDx
            $cyBest = $cy0+$bestDy
            $radii = New-Object System.Collections.Generic.List[double]
            foreach ($q in $cyan) {
                $rx=$q.X-$cxBest; $ry=$q.Y-$cyBest
                $d=[Math]::Sqrt($rx*$rx+$ry*$ry)
                if ([Math]::Abs($d-$expectedR) -le 6.0) { $radii.Add($d) }
            }
            if ($radii.Count -lt 12) { continue }
            $radius = Median ([double[]]$radii.ToArray())
            $ppu = ($radius / $p.Footprint) / $scaleX
            if ([double]::IsNaN($ppu) -or $ppu -lt 18 -or $ppu -gt 34) { continue }
            $offsetX = $bestDx / $scaleX
            $offsetY = $bestDy / $scaleY
            if ([Math]::Abs($offsetX) -gt 14 -or [Math]::Abs($offsetY) -gt 14) { continue }

            $samples.Add([PSCustomObject]@{
                PPU=$ppu; OffsetX=$offsetX; OffsetY=$offsetY; Support=$bestScore; Slot=$p.Slot
            })
        }

        if ($samples.Count -lt 3) {
            Log ("CALIBRATION SKIP map={0} result={1}: only {2} usable cyan ring sample(s). Default 26 px/unit retained." -f $MapName,$Result,$samples.Count)
            exit 0
        }

        $ppuValues = [double[]]@($samples | ForEach-Object {$_.PPU})
        $oxValues = [double[]]@($samples | ForEach-Object {$_.OffsetX})
        $oyValues = [double[]]@($samples | ForEach-Object {$_.OffsetY})
        $ppuMedian = Median $ppuValues
        $oxMedian = Median $oxValues
        $oyMedian = Median $oyValues

        # Trim gross disagreements around the robust median before the final estimate.
        $kept = @($samples | Where-Object {
            [Math]::Abs($_.PPU-$ppuMedian) -le 3.0 -and
            [Math]::Abs($_.OffsetX-$oxMedian) -le 6.0 -and
            [Math]::Abs($_.OffsetY-$oyMedian) -le 6.0
        })
        if ($kept.Count -ge 3) {
            $ppuMedian = Median ([double[]]@($kept | ForEach-Object {$_.PPU}))
            $oxMedian = Median ([double[]]@($kept | ForEach-Object {$_.OffsetX}))
            $oyMedian = Median ([double[]]@($kept | ForEach-Object {$_.OffsetY}))
        } else {
            $kept = @($samples)
        }

        $confidence = [Math]::Min(1.0, $kept.Count / 8.0)
        $key = Safe-Key $MapName
        if (!$key) { throw 'Map key became empty.' }
        $out = Join-Path $calibrationDir ($key + '.ini')
        $text = @"
[Geometry]
PixelsPerUnit=$([Math]::Round($ppuMedian,3))
OffsetX=$([Math]::Round($oxMedian,3))
OffsetY=$([Math]::Round($oyMedian,3))
Samples=$($kept.Count)
Confidence=$([Math]::Round($confidence,3))
Source=postrun-cyan
Result=$Result
CapturedAt=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Screenshot=$Screenshot
"@
        [IO.File]::WriteAllText($out,$text,(New-Object Text.UTF8Encoding($false)))
        Log ("CALIBRATED map={0} result={1}: ppu={2:N3} offset=({3:N2},{4:N2}) samples={5} confidence={6:N2}" -f $MapName,$Result,$ppuMedian,$oxMedian,$oyMedian,$kept.Count,$confidence)
    }
    finally {
        if ($data) { $bmp.UnlockBits($data) }
        if ($bmp) { $bmp.Dispose() }
        if ($src) { $src.Dispose() }
    }
}
catch {
    Log ('ERROR ' + $_.Exception.ToString())
    exit 0
}

exit 0
