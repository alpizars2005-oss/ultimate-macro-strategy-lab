param(
    [string]$InstallDir = (Get-Location).Path,
    [switch]$RebuildMain,
    [switch]$ResetLabRuntime,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$RepoUrl = 'https://github.com/alpizars2005-oss/ultimate-macro-strategy-lab.git'
$localRoot = Join-Path $env:LOCALAPPDATA 'Ultimate_Macro\StrategyLabCleanInstall'
$cacheRepo = Join-Path $localRoot 'repo'
$logPath = Join-Path $localRoot 'install.log'
New-Item -ItemType Directory -Force -Path $localRoot | Out-Null

function Log([string]$Text) {
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text)
}

function Write-Utf8NoBom([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}

function Run-Git([string[]]$Arguments,[switch]$Visible) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'git.exe'
    $psi.WorkingDirectory = $localRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = !$Visible
    $psi.RedirectStandardOutput = !$Visible
    $psi.RedirectStandardError = !$Visible
    $quoted = foreach ($arg in $Arguments) {
        if ($arg -match '[\s"]') { '"' + ($arg -replace '"','\"') + '"' } else { $arg }
    }
    $psi.Arguments = ($quoted -join ' ')
    $p = New-Object Diagnostics.Process
    $p.StartInfo = $psi
    if (!$p.Start()) { throw 'Could not launch git.exe.' }
    $p.WaitForExit()
    if (!$Visible) {
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        if ($stdout) { Log ('GIT OUT ' + ($stdout.Trim() -replace "`r?`n", ' | ')) }
        if ($stderr) { Log ('GIT ERR ' + ($stderr.Trim() -replace "`r?`n", ' | ')) }
    }
    return $p.ExitCode
}

function Refresh-Repo {
    try { & git.exe --version *> $null }
    catch { throw 'Git for Windows is required for the private Strategy Lab update channel.' }

    if (!(Test-Path -LiteralPath (Join-Path $cacheRepo '.git') -PathType Container)) {
        if (Test-Path -LiteralPath $cacheRepo) { Remove-Item -LiteralPath $cacheRepo -Recurse -Force }
        Write-Host 'Connecting to the private Strategy Lab repository...' -ForegroundColor Cyan
        Write-Host 'GitHub may open a browser once through Git Credential Manager.' -ForegroundColor DarkGray
        $code = Run-Git @('clone','--depth','1','--branch','main',$RepoUrl,$cacheRepo) -Visible
        if ($code -ne 0) { throw "Private repository clone failed (git exit $code)." }
        return
    }

    $code = Run-Git @('-C',$cacheRepo,'fetch','--quiet','--depth','1','origin','main')
    if ($code -ne 0) { throw "Private repository fetch failed (git exit $code)." }
    $code = Run-Git @('-C',$cacheRepo,'reset','--quiet','--hard','FETCH_HEAD')
    if ($code -ne 0) { throw "Private repository reset failed (git exit $code)." }
}

function Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Install-StableFiles([string]$Root) {
    $channel = Join-Path $cacheRepo 'channel\stable'
    $manifest = Join-Path $channel 'files.manifest'
    $versionPath = Join-Path $channel 'version.ini'
    if (!(Test-Path -LiteralPath $manifest) -or !(Test-Path -LiteralPath $versionPath)) {
        throw 'Stable update channel is incomplete.'
    }

    $versionText = Get-Content -LiteralPath $versionPath -Raw
    if ($versionText -notmatch '(?im)^Version\s*=\s*([^\r\n]+)') { throw 'Invalid stable version.ini.' }
    $version = $Matches[1].Trim()
    $installed = 0
    $unchanged = 0

    foreach ($raw in Get-Content -LiteralPath $manifest) {
        $line = $raw.Trim()
        if (!$line -or $line.StartsWith('#')) { continue }
        $parts = $line.Split('|')
        if ($parts.Count -ne 4) { throw "Invalid manifest line: $line" }
        $expected = $parts[0].Trim().ToLowerInvariant()
        $target = $parts[1].Trim().Replace('/','\')
        $source = $parts[2].Trim().Replace('/','\')
        $mode = $parts[3].Trim().ToLowerInvariant()

        if ($target.ToLowerInvariant().StartsWith('resources\strats\')) { continue }
        if ($target.Contains('..') -or [IO.Path]::IsPathRooted($target)) { throw "Unsafe manifest target: $target" }
        if ($expected -notmatch '^[0-9a-f]{64}$') { throw "Invalid manifest hash: $line" }

        $sourcePath = Join-Path $cacheRepo $source
        if (!(Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Missing stable source: $source" }
        $targetPath = Join-Path $Root $target

        # Reinstalling Strategy Lab is common during development. Avoid rewriting a file
        # when the installed bytes already match the signed manifest entry. Besides being
        # faster, this reduces filesystem churn while iterating on the editor.
        if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            try {
                if ((Sha256 $targetPath) -eq $expected) {
                    $unchanged++
                    continue
                }
            } catch {
                # Fall through to the normal verified replacement path.
            }
        }

        $parent = Split-Path -Parent $targetPath
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        $tmp = Join-Path $env:TEMP ('strategy-lab-clean-' + [guid]::NewGuid().ToString('N'))
        try {
            if ($mode -eq 'base64') {
                $b64 = (Get-Content -LiteralPath $sourcePath -Raw).Trim()
                [IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String($b64))
            } elseif ($mode -eq 'raw') {
                Copy-Item -LiteralPath $sourcePath -Destination $tmp -Force
            } else {
                throw "Unsupported manifest mode: $mode"
            }
            $actual = Sha256 $tmp
            if ($actual -ne $expected) { throw "SHA-256 mismatch for $target" }
            Move-Item -LiteralPath $tmp -Destination $targetPath -Force
            $installed++
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    Log ("FILES installed={0} unchanged={1}" -f $installed,$unchanged)
    return $version
}

function Replace-ExactlyOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $count = ([regex]::Matches($Text,[regex]::Escape($Old))).Count
    if ($count -ne 1) { throw "${Label}: expected exactly one baseline anchor, found $count." }
    return $Text.Replace($Old,$New)
}

function Patch-TabDeclaration([string]$Text) {
    $pattern = '(?m)^(?<indent>[ \t]*)tabNames\s*:=\s*\[(?<body>[^\r\n]*)\][ \t]*$'
    $matches = [regex]::Matches($Text,$pattern)
    if ($matches.Count -ne 1) {
        throw "Could not identify one unambiguous tabNames declaration (found $($matches.Count))."
    }

    $match = $matches[0]
    $labels = New-Object 'System.Collections.Generic.List[string]'
    foreach ($labelMatch in [regex]::Matches($match.Groups['body'].Value,'"([^"]+)"')) {
        [void]$labels.Add($labelMatch.Groups[1].Value)
    }
    if ($labels.Count -lt 2) { throw 'tabNames declaration did not contain enough labels.' }

    $creditsZero = -1
    $editorZero = -1
    $statsZero = -1
    for ($i = 0; $i -lt $labels.Count; $i++) {
        if ([string]::Equals($labels[$i],'Credits',[StringComparison]::OrdinalIgnoreCase)) { $creditsZero = $i }
        if ([string]::Equals($labels[$i],'Editor',[StringComparison]::OrdinalIgnoreCase)) { $editorZero = $i }
        if ([string]::Equals($labels[$i],'Stats',[StringComparison]::OrdinalIgnoreCase)) { $statsZero = $i }
    }
    if ($creditsZero -lt 0) { throw 'Could not locate Credits in tabNames.' }
    if (($editorZero -ge 0) -xor ($statsZero -ge 0)) {
        throw 'Only one Strategy Lab tab is present in tabNames; refusing an ambiguous partial patch.'
    }

    if ($editorZero -ge 0 -and $statsZero -ge 0) {
        if ($editorZero + 1 -ne $statsZero -or $statsZero + 1 -ne $creditsZero) {
            throw 'Existing Editor/Stats tabs are not immediately before Credits.'
        }
        return [PSCustomObject]@{
            Text = $Text
            OldCreditsIndex = $creditsZero - 1
            EditorIndex = $editorZero + 1
            StatsIndex = $statsZero + 1
            CreditsIndex = $creditsZero + 1
            TabCount = $labels.Count
            AlreadyPatched = $true
        }
    }

    $oldCreditsIndex = $creditsZero + 1
    $labels.Insert($creditsZero,'Editor')
    $labels.Insert($creditsZero + 1,'Stats')
    $quoted = foreach ($label in $labels) { '"' + $label + '"' }
    $newLine = $match.Groups['indent'].Value + 'tabNames := [' + ($quoted -join ', ') + ']'
    $patched = $Text.Substring(0,$match.Index) + $newLine + $Text.Substring($match.Index + $match.Length)

    return [PSCustomObject]@{
        Text = $patched
        OldCreditsIndex = $oldCreditsIndex
        EditorIndex = $oldCreditsIndex
        StatsIndex = $oldCreditsIndex + 1
        CreditsIndex = $oldCreditsIndex + 2
        TabCount = $labels.Count
        AlreadyPatched = $false
    }
}

function Patch-MainLab([string]$MainPath,[string]$Version) {
    $text = [IO.File]::ReadAllText($MainPath)
    if ($text -match '(?m)^(<<<<<<<|=======|>>>>>>>)') { throw 'Main_Lab.ahk contains merge markers.' }

    if (!$text.Contains('; <StrategyLabClean039>')) {
        $includeAnchor = '#Include lib\Discord.ahk'
        $includeBlock = $includeAnchor + "`r`n" +
            '; <StrategyLabClean039>' + "`r`n" +
            '#Include lib\StrategyLab\StrategyEditorTab.ahk' + "`r`n" +
            '#Include lib\StrategyLab\LabUpdater.ahk' + "`r`n" +
            '; </StrategyLabClean039>'
        $text = Replace-ExactlyOnce $text $includeAnchor $includeBlock 'Strategy Lab include injection'
    }

    # Upstream 1.3.3 changed tab labels. Parse the actual array instead of pinning the
    # installer to one exact historical string; preserve every upstream label verbatim
    # and insert Strategy Lab immediately before Credits.
    $tabPatch = Patch-TabDeclaration $text
    $text = $tabPatch.Text
    Log ("TABS count={0} editor=Tab{1} stats=Tab{2} credits=Tab{3}" -f
        $tabPatch.TabCount,$tabPatch.EditorIndex,$tabPatch.StatsIndex,$tabPatch.CreditsIndex)

    # The current upstream GUI is 700 px wide. Nine tabs fit comfortably with this compact
    # geometry. These replacements are intentionally no-ops when an already-patched file
    # is reprocessed.
    $text = $text.Replace('xTab := 20 + (i-1) * 90','xTab := 10 + (i-1) * 76')
    $text = $text.Replace('"x" xTab " y43 w80 h34 Hidden Background222222 Disabled"','"x" xTab " y43 w72 h34 Hidden Background222222 Disabled"')
    $text = $text.Replace('"x" xTab " y52 w80 h22 Center BackgroundTrans"','"x" xTab " y52 w72 h22 Center BackgroundTrans"')
    $text = $text.Replace('global TabLine := MainGui.Add("Progress", "x20 y75 w80 h2 BackgroundFFFFFF", 0)','global TabLine := MainGui.Add("Progress", "x10 y75 w72 h2 BackgroundFFFFFF", 0)')
    $text = $text.Replace('newX := 20 + (idx - 1) * 90','newX := 10 + (idx - 1) * 76')
    $text = $text.Replace('TabLine.Move(newX, , 80)','TabLine.Move(newX, , 72)')

    if (!$text.Contains('; <StrategyLabTabControls>')) {
        $anchor = 'MainGui.Title := "Ultimate Macro"'
        $block = '; <StrategyLabTabControls>' + "`r`n" +
            'StrategyEditorCreateTab(MainGui)' + "`r`n" +
            'LabStatsCreateTab(MainGui)' + "`r`n" +
            '; </StrategyLabTabControls>' + "`r`n" +
            'MainGui.Title := "Ultimate Macro | Strategy Lab"'
        $text = Replace-ExactlyOnce $text $anchor $block 'Strategy Lab tab-control injection'
    }

    if (!$text.Contains('StrategyEditorShow()') -or !$text.Contains('LabStatsShow()')) {
        $creditsPattern = '(?ms)\}\s*else if\s*\(tab\s*=\s*"Tab' + $tabPatch.OldCreditsIndex + '"\)\s*\{\r?\n(?<body>\s*Credit_Content\.Visible\s*:=\s*true.*?\s*Credit_InfoBG\.Visible\s*:=\s*true\r?\n)\s*\}'
        $creditsMatches = [regex]::Matches($text,$creditsPattern)
        if ($creditsMatches.Count -ne 1) {
            throw "ShowTabContent integration anchor is ambiguous (found $($creditsMatches.Count) baseline Credits blocks for Tab$($tabPatch.OldCreditsIndex))."
        }
        $body = $creditsMatches[0].Groups['body'].Value
        $replacement = '} else if (tab = "Tab' + $tabPatch.EditorIndex + '") {' + "`r`n" +
            '        StrategyEditorShow()' + "`r`n" +
            '    } else if (tab = "Tab' + $tabPatch.StatsIndex + '") {' + "`r`n" +
            '        LabStatsShow()' + "`r`n" +
            '    } else if (tab = "Tab' + $tabPatch.CreditsIndex + '") {' + "`r`n" + $body + '    }'
        $text = $text.Substring(0,$creditsMatches[0].Index) + $replacement + $text.Substring($creditsMatches[0].Index + $creditsMatches[0].Length)
    }

    if (!$text.Contains('; <StrategyLabUpdaterStartup>')) {
        $startupAnchor = 'ShowTabContent("Tab1")' + "`r`n" + 'ShowChildGui()' + "`r`n" + 'EnableStratRotation()'
        if (!$text.Contains($startupAnchor)) {
            $startupAnchor = 'ShowTabContent("Tab1")' + "`n" + 'ShowChildGui()' + "`n" + 'EnableStratRotation()'
        }
        if (!$text.Contains($startupAnchor)) { throw 'Could not locate startup tab sequence.' }
        $startupBlock = $startupAnchor + "`r`n" +
            '; <StrategyLabUpdaterStartup>' + "`r`n" +
            'SetTimer(LabUpdaterStartupCheck.Bind("' + $Version + '"), -1800)' + "`r`n" +
            '; </StrategyLabUpdaterStartup>'
        $text = $text.Replace($startupAnchor,$startupBlock)
    }

    Write-Utf8NoBom $MainPath $text
}

function Reset-LabRuntimeState {
    $editorRoot = Join-Path $env:APPDATA 'Ultimate_Macro\StrategyEditor'
    if (Test-Path -LiteralPath $editorRoot) {
        Remove-Item -LiteralPath $editorRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    foreach ($path in @(
        (Join-Path $env:APPDATA 'Ultimate_Macro\remote_command.ini'),
        (Join-Path $env:LOCALAPPDATA 'Ultimate_Macro\StrategyLabUpdater')
    )) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

try {
    $InstallDir = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallDir.Trim()).Trim('"'))
    if (!(Test-Path -LiteralPath $InstallDir -PathType Container)) { throw "Install folder does not exist: $InstallDir" }
    $baseline = Join-Path $InstallDir 'Main.ahk'
    if (!(Test-Path -LiteralPath $baseline -PathType Leaf)) { throw "Main.ahk baseline was not found in $InstallDir" }

    Log ("BEGIN clean install root={0}" -f $InstallDir)
    if ($ResetLabRuntime) { Reset-LabRuntimeState; Log 'RESET Lab runtime/cache state.' }
    Refresh-Repo
    $version = Install-StableFiles $InstallDir

    $mainLab = Join-Path $InstallDir 'Main_Lab.ahk'
    if ($RebuildMain -or !(Test-Path -LiteralPath $mainLab -PathType Leaf)) {
        Copy-Item -LiteralPath $baseline -Destination $mainLab -Force
        Log 'REBUILD Main_Lab.ahk from clean Main.ahk baseline.'
    }
    Patch-MainLab $mainLab $version

    $preflight = Join-Path $InstallDir 'submacros\lab_preflight.ps1'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $preflight -InstallDir $InstallDir
    if ($LASTEXITCODE -ne 0) { throw "Strategy Lab preflight failed with exit code $LASTEXITCODE." }

    $remoteSettings = Join-Path $InstallDir 'submacros\lab_remote_settings.ps1'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $remoteSettings -InstallDir $InstallDir -SelfTest
    if ($LASTEXITCODE -ne 0) { throw "Discord Remote self-test failed with exit code $LASTEXITCODE." }

    $probe = Join-Path $InstallDir 'submacros\lab_syntax_probe.ps1'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $probe -InstallDir $InstallDir
    if ($LASTEXITCODE -ne 0) { throw "AutoHotkey integrated syntax probe failed with exit code $LASTEXITCODE." }

    Write-Utf8NoBom (Join-Path $InstallDir 'lab_version.ini') ("[Lab]`r`nVersion=$version`r`n")
    Log ("SUCCESS clean install version={0}" -f $version)
    Write-Host "`nSUCCESS: clean Strategy Lab $version installation validated." -ForegroundColor Green

    if (!$NoLaunch) {
        Start-Process -FilePath (Join-Path $InstallDir 'run_lab.bat') -WorkingDirectory $InstallDir | Out-Null
    }
} catch {
    Log ('FAILED ' + $_.Exception.ToString())
    Write-Host "`nCLEAN INSTALL FAILED SAFELY" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Log: $logPath" -ForegroundColor Yellow
    exit 1
}
