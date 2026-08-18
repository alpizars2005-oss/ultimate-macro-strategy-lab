param(
    [Parameter(Mandatory=$true)][string]$InstallDir
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$root = Join-Path $env:APPDATA 'Ultimate_Macro\StrategyEditor'
$configPath = Join-Path $root 'remote.ini'
$statePath = Join-Path $env:APPDATA 'Ultimate_Macro\state.ini'
$remoteCommandPath = Join-Path $env:APPDATA 'Ultimate_Macro\remote_command.ini'
$labCommandPath = Join-Path $root 'lab_remote_command.ini'
$telemetryDir = Join-Path $root 'telemetry'
$heartbeatPath = Join-Path $telemetryDir 'heartbeat.ini'
$logPath = Join-Path $root 'discord-worker.log'
$stratsDir = Join-Path $InstallDir 'Resources\Strats'
$apiBase = 'https://discord.com/api/v10'
New-Item -ItemType Directory -Force -Path $root | Out-Null

$createdNew = $false
$mutex = New-Object Threading.Mutex($true, 'UltimateMacroStrategyLabDiscordWorker', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

function Log([string]$Text) {
    try { Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text) } catch {}
}

function Read-Ini([string]$Path) {
    $result = @{}
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $result }
    $section = ''
    foreach ($raw in [IO.File]::ReadAllLines($Path)) {
        $line = $raw.Trim()
        if (!$line -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }
        if ($line.StartsWith('[') -and $line.EndsWith(']')) {
            $section = $line.Substring(1, $line.Length - 2).Trim().ToLowerInvariant()
            if (!$result.ContainsKey($section)) { $result[$section] = @{} }
            continue
        }
        $eq = $line.IndexOf('=')
        if ($eq -gt 0 -and $section) {
            $key = $line.Substring(0, $eq).Trim().ToLowerInvariant()
            $value = $line.Substring($eq + 1).Trim()
            $result[$section][$key] = $value
        }
    }
    return $result
}

function Ini-Value($Data, [string]$Section, [string]$Key, [string]$Default='') {
    $s = $Section.ToLowerInvariant(); $k = $Key.ToLowerInvariant()
    if ($Data.ContainsKey($s) -and $Data[$s].ContainsKey($k)) { return [string]$Data[$s][$k] }
    return $Default
}

function Decrypt-Token([string]$Cipher) {
    if ([string]::IsNullOrWhiteSpace($Cipher)) { return '' }
    try {
        $bytes = [Convert]::FromBase64String($Cipher)
        $plain = [Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [Text.Encoding]::UTF8.GetString($plain)
    } catch {
        Log ('ERROR token decrypt failed: ' + $_.Exception.Message)
        return ''
    }
}

function Get-RemoteConfig {
    $ini = Read-Ini $configPath
    $poll = 4
    try { $poll = [int](Ini-Value $ini 'Remote' 'PollSeconds' '4') } catch { $poll = 4 }
    return [pscustomobject]@{
        Enabled = (Ini-Value $ini 'Remote' 'Enabled' '0') -eq '1'
        ChannelID = Ini-Value $ini 'Remote' 'ChannelID' ''
        UserID = Ini-Value $ini 'Remote' 'UserID' ''
        PollSeconds = [Math]::Max(2, [Math]::Min(30, $poll))
        Token = Decrypt-Token (Ini-Value $ini 'Remote' 'TokenProtected' '')
    }
}

function Discord-Headers([string]$Token) {
    return @{ Authorization = ('Bot ' + $Token); 'User-Agent' = 'UltimateMacroStrategyLab/0.3' }
}

function Send-DiscordText([string]$Token, [string]$Channel, [string]$Text, [string]$ReplyTo='') {
    if ($Text.Length -gt 1950) { $Text = $Text.Substring(0, 1950) + "`n…" }
    $payload = @{ content = $Text; allowed_mentions = @{ parse = @() } }
    if ($ReplyTo) { $payload.message_reference = @{ message_id = $ReplyTo; fail_if_not_exists = $false } }
    $json = $payload | ConvertTo-Json -Depth 6 -Compress
    try {
        Invoke-RestMethod -Uri "$apiBase/channels/$Channel/messages" -Method Post -Headers (Discord-Headers $Token) -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($json)) | Out-Null
        return $true
    } catch {
        Log ('ERROR send message: ' + $_.Exception.Message)
        return $false
    }
}

function Get-RobloxCapturePath {
    $temp = Join-Path $env:TEMP ('strategy-lab-' + [guid]::NewGuid().ToString('N') + '.jpg')
    $bounds = [Windows.Forms.SystemInformation]::VirtualScreen
    $proc = Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.MainWindowHandle -ne 0) {
        if (-not ('LabNativeWindow' -as [type])) {
            Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LabNativeWindow {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
}
'@
        }
        $r = New-Object LabNativeWindow+RECT
        if ([LabNativeWindow]::GetWindowRect($proc.MainWindowHandle, [ref]$r)) {
            $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
            if ($w -gt 200 -and $h -gt 200) { $bounds = New-Object Drawing.Rectangle($r.Left, $r.Top, $w, $h) }
        }
    }

    $bmp = New-Object Drawing.Bitmap($bounds.Width, $bounds.Height, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
        $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg' | Select-Object -First 1
        $enc = New-Object Drawing.Imaging.EncoderParameters(1)
        $enc.Param[0] = New-Object Drawing.Imaging.EncoderParameter([Drawing.Imaging.Encoder]::Quality, [long]82)
        $bmp.Save($temp, $codec, $enc)
    } finally {
        $g.Dispose(); $bmp.Dispose()
    }
    return $temp
}

function Send-DiscordScreenshot([string]$Token, [string]$Channel, [string]$ReplyTo='') {
    $path = $null
    $client = $null
    try {
        $path = Get-RobloxCapturePath
        $client = New-Object Net.Http.HttpClient
        $client.DefaultRequestHeaders.Authorization = New-Object Net.Http.Headers.AuthenticationHeaderValue('Bot', $Token)
        $client.DefaultRequestHeaders.UserAgent.ParseAdd('UltimateMacroStrategyLab/0.3')
        $form = New-Object Net.Http.MultipartFormDataContent
        $payload = @{ content = 'Requested screenshot'; allowed_mentions = @{ parse = @() } }
        if ($ReplyTo) { $payload.message_reference = @{ message_id = $ReplyTo; fail_if_not_exists = $false } }
        $json = $payload | ConvertTo-Json -Depth 5 -Compress
        $jsonContent = New-Object Net.Http.StringContent($json, [Text.Encoding]::UTF8, 'application/json')
        $form.Add($jsonContent, 'payload_json')
        $bytes = [IO.File]::ReadAllBytes($path)
        $fileContent = New-Object Net.Http.ByteArrayContent($bytes)
        $fileContent.Headers.ContentType = New-Object Net.Http.Headers.MediaTypeHeaderValue('image/jpeg')
        $form.Add($fileContent, 'files[0]', 'screenshot.jpg')
        $response = $client.PostAsync("$apiBase/channels/$Channel/messages", $form).GetAwaiter().GetResult()
        if (!$response.IsSuccessStatusCode) { throw "Discord upload returned HTTP $([int]$response.StatusCode)" }
        return $true
    } catch {
        Log ('ERROR screenshot: ' + $_.Exception.Message)
        return $false
    } finally {
        if ($client) { $client.Dispose() }
        if ($path -and (Test-Path -LiteralPath $path)) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
}

function Write-AtomicIni([string]$Path, [string[]]$Lines) {
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $tmp = $Path + '.tmp'
    [IO.File]::WriteAllText($tmp, (($Lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Queue-MacroCommand([string]$Action, [string]$Strategy='') {
    $lines = @('[Command]', ('Id=' + [guid]::NewGuid().ToString('N')), ('Action=' + $Action), ('RequestedAt=' + [DateTime]::UtcNow.ToString('o')))
    if ($Strategy) { $lines += ('Strategy=' + $Strategy) }
    Write-AtomicIni $remoteCommandPath $lines
}

function Queue-LabCommand([string]$Action, [string]$Value='') {
    $lines = @('[Command]', ('Id=' + [guid]::NewGuid().ToString('N')), ('Action=' + $Action), ('Value=' + $Value), ('RequestedAt=' + [DateTime]::UtcNow.ToString('o')))
    Write-AtomicIni $labCommandPath $lines
}

function Get-Strategies {
    if (!(Test-Path -LiteralPath $stratsDir -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $stratsDir -Filter '*.strat' -File | Sort-Object Name)
}

function Resolve-Strategy([string]$Query) {
    $q = $Query.Trim()
    if (!$q) { return $null }
    $all = Get-Strategies
    $exact = @($all | Where-Object { $_.Name -ieq $q -or $_.BaseName -ieq $q })
    if ($exact.Count -ge 1) { return $exact[0] }
    $matches = @($all | Where-Object { $_.BaseName.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    if ($matches.Count -eq 1) { return $matches[0] }
    return $null
}

function Macro-ProcessRunning {
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe' OR Name='AutoHotkey32.exe' OR Name='AutoHotkey.exe'" -ErrorAction Stop
        foreach ($p in $procs) {
            if ($p.CommandLine -and $p.CommandLine.IndexOf('Main_Lab.ahk', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        }
    } catch {}
    return $false
}

function Ensure-MacroRunning {
    if (Macro-ProcessRunning) { return }
    $launcher = Join-Path $InstallDir 'run_lab.bat'
    if (Test-Path -LiteralPath $launcher) { Start-Process -FilePath $launcher -WorkingDirectory $InstallDir -WindowStyle Hidden }
}

function Build-Status {
    $s = Read-Ini $statePath
    $h = Read-Ini $heartbeatPath
    $running = (Ini-Value $s 'State' 'Running' '0') -eq '1'
    $strategy = Ini-Value $s 'State' 'Strategy' 'None'
    if ($strategy -and $strategy -ne '0') { $strategy = [IO.Path]::GetFileName($strategy) }
    $wins = [int](Ini-Value $s 'State' 'TotalTriumphs' '0')
    $losses = [int](Ini-Value $s 'State' 'TotalLosses' '0')
    $coins = Ini-Value $s 'State' 'Coins' '0'; $gems = Ini-Value $s 'State' 'Gems' '0'; $exp = Ini-Value $s 'State' 'EXP' '0'
    $runs = Ini-Value $s 'State' 'CurrentRunCount' '0'
    $phaseDefault = $(if ($running) { 'running' } else { 'stopped' })
    $phase = Ini-Value $h 'Heartbeat' 'Phase' $phaseDefault
    $remote = Ini-Value $s 'Remote' 'LastResult' 'none'
    $total = $wins + $losses; $wr = if ($total -gt 0) { [Math]::Round(($wins / $total) * 100, 1) } else { 0 }
    return "**Ultimate Macro Strategy Lab**`nStatus: " + ($(if ($running) {'🟢 Running'} else {'⚫ Stopped'})) + "`nPhase: ``$phase```nStrategy: ``$strategy```nRuns: $runs | Wins: $wins | Losses: $losses | WR: $wr%`nCoins: $coins | Gems: $gems | EXP: $exp`nLast remote result: ``$remote``"
}

function Process-Command($Msg, $Cfg) {
    $content = ([string]$Msg.content).Trim()
    if (!$content.StartsWith('!')) { return }
    $lower = $content.ToLowerInvariant()
    $id = [string]$Msg.id

    if ($lower -eq '!help') {
        Send-DiscordText $Cfg.Token $Cfg.ChannelID "**Strategy Lab Remote**`n!status`n!screenshot`n!start <strategy>`n!switch <strategy>`n!stop`n!stop now`n!strategy list`n!strategy <strategy>`n!rings all|selected|off`n!recalibrate`n!ping" $id | Out-Null
        return
    }
    if ($lower -eq '!ping') { Send-DiscordText $Cfg.Token $Cfg.ChannelID '🏓 Strategy Lab remote is alive.' $id | Out-Null; return }
    if ($lower -eq '!status') { Send-DiscordText $Cfg.Token $Cfg.ChannelID (Build-Status) $id | Out-Null; return }
    if ($lower -eq '!screenshot') {
        if (!(Send-DiscordScreenshot $Cfg.Token $Cfg.ChannelID $id)) { Send-DiscordText $Cfg.Token $Cfg.ChannelID '❌ Screenshot failed. Check discord-worker.log.' $id | Out-Null }
        return
    }
    if ($lower -eq '!stop now') { Queue-LabCommand 'emergency_stop'; Send-DiscordText $Cfg.Token $Cfg.ChannelID '🛑 Emergency stop sent; held inputs will be released.' $id | Out-Null; return }
    if ($lower -eq '!stop') { Queue-MacroCommand 'stop'; Send-DiscordText $Cfg.Token $Cfg.ChannelID '⏹️ Safe stop queued for the next between-match boundary.' $id | Out-Null; return }
    if ($lower -match '^!rings\s+(all|selected|off)$') { Queue-LabCommand 'rings' $Matches[1]; Send-DiscordText $Cfg.Token $Cfg.ChannelID ("⭕ Placement circles: " + $Matches[1]) $id | Out-Null; return }
    if ($lower -eq '!recalibrate') { Queue-LabCommand 'recalibrate'; Send-DiscordText $Cfg.Token $Cfg.ChannelID '📐 Current map calibration cleared. The next clean capture can replace it.' $id | Out-Null; return }
    if ($lower -eq '!strategy list') {
        $items = Get-Strategies
        if ($items.Count -eq 0) { Send-DiscordText $Cfg.Token $Cfg.ChannelID 'No .strat files found.' $id | Out-Null; return }
        $lines = @(); $i = 1
        foreach ($f in $items | Select-Object -First 35) { $lines += ("$i. ``" + $f.BaseName + '``'); $i++ }
        if ($items.Count -gt 35) { $lines += ('…and ' + ($items.Count - 35) + ' more.') }
        Send-DiscordText $Cfg.Token $Cfg.ChannelID ("**Available strategies**`n" + ($lines -join "`n")) $id | Out-Null
        return
    }

    $mode = $null; $query = ''
    if ($content -match '^!start\s+(.+)$') { $mode = 'start'; $query = $Matches[1] }
    elseif ($content -match '^!switch\s+(.+)$') { $mode = 'switch'; $query = $Matches[1] }
    elseif ($content -match '^!strategy\s+(.+)$') { $mode = 'strategy'; $query = $Matches[1] }
    if ($mode) {
        $strat = Resolve-Strategy $query
        if (!$strat) { Send-DiscordText $Cfg.Token $Cfg.ChannelID '❌ Strategy not found or the search matched more than one file.' $id | Out-Null; return }
        $s = Read-Ini $statePath; $running = (Ini-Value $s 'State' 'Running' '0') -eq '1'
        if ($mode -eq 'strategy') { $mode = $(if ($running) {'switch'} else {'start'}) }
        if ($mode -eq 'start' -and $running) { Send-DiscordText $Cfg.Token $Cfg.ChannelID '⚠️ Macro is already running. Use !switch <strategy>.' $id | Out-Null; return }
        if ($mode -eq 'switch' -and !$running) { $mode = 'start' }
        Queue-MacroCommand $mode $strat.FullName
        Ensure-MacroRunning
        Send-DiscordText $Cfg.Token $Cfg.ChannelID ($(if ($mode -eq 'switch') {"🔄 Queued **$($strat.BaseName)** for the next safe boundary."} else {"▶️ Start queued for **$($strat.BaseName)**."})) $id | Out-Null
        return
    }
}

try {
    Log 'worker started'
    $lastMessage = ''
    while ($true) {
        $cfg = Get-RemoteConfig
        if (!$cfg.Enabled) { Log 'worker exiting: disabled'; break }
        if (!$cfg.Token -or !$cfg.ChannelID -or !$cfg.UserID) { Log 'worker waiting: incomplete config'; Start-Sleep -Seconds 5; continue }
        try {
            $headers = Discord-Headers $cfg.Token
            if (!$lastMessage) {
                $seed = @(Invoke-RestMethod -Uri "$apiBase/channels/$($cfg.ChannelID)/messages?limit=1" -Headers $headers -Method Get)
                if ($seed.Count -gt 0) { $lastMessage = [string]$seed[0].id }
                Log ('cursor seeded at ' + $lastMessage)
            } else {
                $messages = @(Invoke-RestMethod -Uri "$apiBase/channels/$($cfg.ChannelID)/messages?after=$lastMessage&limit=50" -Headers $headers -Method Get)
                if ($messages.Count -gt 0) {
                    foreach ($msg in ($messages | Sort-Object { [decimal]$_.id })) {
                        $lastMessage = [string]$msg.id
                        if ([string]$msg.author.id -ne [string]$cfg.UserID) { continue }
                        Process-Command $msg $cfg
                    }
                }
            }
        } catch {
            Log ('ERROR poll: ' + $_.Exception.Message)
        }
        Start-Sleep -Seconds $cfg.PollSeconds
    }
} finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
