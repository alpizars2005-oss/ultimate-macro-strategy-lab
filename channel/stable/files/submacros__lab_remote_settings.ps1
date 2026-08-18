param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:APPDATA 'Ultimate_Macro\StrategyEditor'
$logPath = Join-Path $root 'remote-settings.log'
New-Item -ItemType Directory -Force -Path $root | Out-Null

function Log([string]$Text) {
    try { Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text) } catch {}
}

function Show-Fatal([string]$Message) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [Windows.Forms.MessageBox]::Show(
            $Message + "`r`n`r`nSee:`r`n" + $logPath,
            'Strategy Lab Remote',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch {}
}

try {
    $candidate = [Environment]::ExpandEnvironmentVariables($InstallDir.Trim()).Trim('"')
    $InstallDir = [IO.Path]::GetFullPath($candidate)
    if (!(Test-Path -LiteralPath $InstallDir -PathType Container)) { throw "Install directory does not exist: $InstallDir" }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    try { Add-Type -AssemblyName System.Security -ErrorAction Stop } catch { Log ('INFO System.Security already available/not separately loadable: ' + $_.Exception.Message) }
    [Windows.Forms.Application]::EnableVisualStyles()

    # Runtime regression guard for the PowerShell 5.1 constructor bug which previously
    # produced: System.Object[] does not contain a method named op_Subtraction.
    $constructorProbe = [Drawing.Point]::new(180, (95 - 2))
    $sizeProbe = [Drawing.Size]::new(330, 24)
    if ($constructorProbe.X -ne 180 -or $constructorProbe.Y -ne 93 -or $sizeProbe.Width -ne 330) {
        throw 'WinForms layout constructor self-test failed.'
    }
    if ($SelfTest) {
        Log 'INFO remote settings WinForms constructor self-test passed.'
        exit 0
    }

    $configPath = Join-Path $root 'remote.ini'
    $workerPath = Join-Path $InstallDir 'submacros\lab_discord_worker.ps1'
    $apiBase = 'https://discord.com/api/v10'

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
                $result[$section][$line.Substring(0,$eq).Trim().ToLowerInvariant()] = $line.Substring($eq+1).Trim()
            }
        }
        return $result
    }

    function Ini-Value($Data,[string]$Section,[string]$Key,[string]$Default='') {
        $s=$Section.ToLowerInvariant(); $k=$Key.ToLowerInvariant()
        if($Data.ContainsKey($s) -and $Data[$s].ContainsKey($k)){ return [string]$Data[$s][$k] }
        return $Default
    }

    function Protect-Token([string]$Token) {
        if ([string]::IsNullOrWhiteSpace($Token)) { return '' }
        $bytes=[Text.Encoding]::UTF8.GetBytes($Token)
        $p=[Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [Convert]::ToBase64String($p)
    }

    function Unprotect-Token([string]$Cipher) {
        if(!$Cipher){ return '' }
        try {
            $b=[Convert]::FromBase64String($Cipher)
            $p=[Security.Cryptography.ProtectedData]::Unprotect($b,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
            return [Text.Encoding]::UTF8.GetString($p)
        } catch {
            Log ('WARN existing bot token could not be decrypted: ' + $_.Exception.Message)
            return ''
        }
    }

    function Save-Config([bool]$Enabled,[string]$Token,[string]$Channel,[string]$User,[int]$Poll) {
        $protected = Protect-Token $Token
        $text = "[Remote]`r`nEnabled=" + ($(if($Enabled){'1'}else{'0'})) + "`r`nChannelID=$Channel`r`nUserID=$User`r`nPollSeconds=$Poll`r`nTokenProtected=$protected`r`n"
        [IO.File]::WriteAllText($configPath,$text,(New-Object Text.UTF8Encoding($false)))
        Log ("INFO config saved Enabled={0} Channel={1} User={2} Poll={3}" -f $Enabled,$Channel,$User,$Poll)
    }

    function Send-Test([string]$Token,[string]$Channel) {
        $headers=@{Authorization=('Bot '+$Token);'User-Agent'='UltimateMacroStrategyLab/0.3.7'}
        $payload=@{content='✅ Ultimate Macro Strategy Lab remote is connected.';allowed_mentions=@{parse=@()}} | ConvertTo-Json -Depth 4 -Compress
        Invoke-RestMethod -Uri "$apiBase/channels/$Channel/messages" -Headers $headers -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) | Out-Null
    }

    function Start-DiscordWorker {
        if (!(Test-Path -LiteralPath $workerPath -PathType Leaf)) { throw "Discord worker is missing: $workerPath" }
        $args = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -InstallDir "{1}"' -f $workerPath,$InstallDir
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WorkingDirectory $InstallDir -WindowStyle Hidden -PassThru
        Log ("INFO Discord worker launch requested PID={0}" -f $p.Id)
    }

    $ini=Read-Ini $configPath
    $existingToken=Unprotect-Token (Ini-Value $ini 'Remote' 'TokenProtected' '')

    $form=[Windows.Forms.Form]::new()
    $form.Text='Strategy Lab Remote'
    $form.StartPosition='CenterScreen'
    $form.ClientSize=[Drawing.Size]::new(540,440)
    $form.BackColor=[Drawing.Color]::FromArgb(18,18,18)
    $form.ForeColor=[Drawing.Color]::Gainsboro
    $form.FormBorderStyle='FixedDialog'
    $form.MaximizeBox=$false
    $form.MinimizeBox=$false
    $form.TopMost=$true

    $title=[Windows.Forms.Label]::new()
    $title.Text='Discord Remote'
    $title.Font=[Drawing.Font]::new('Segoe UI',16,[Drawing.FontStyle]::Bold)
    $title.ForeColor=[Drawing.Color]::FromArgb(85,183,255)
    $title.Location=[Drawing.Point]::new(24,18)
    $title.AutoSize=$true
    $form.Controls.Add($title)

    $sub=[Windows.Forms.Label]::new()
    $sub.Text='Private controller • DPAPI-protected token • safe between-match switching'
    $sub.Location=[Drawing.Point]::new(26,55)
    $sub.AutoSize=$true
    $sub.ForeColor=[Drawing.Color]::Gray
    $form.Controls.Add($sub)

    function Add-Label([string]$Text,[int]$Y) {
        $l=[Windows.Forms.Label]::new()
        $l.Text=$Text
        $l.Location=[Drawing.Point]::new(26,$Y)
        $l.Size=[Drawing.Size]::new(150,22)
        $form.Controls.Add($l)
        return $l
    }

    function Add-Text([int]$Y,[string]$Value='') {
        $t=[Windows.Forms.TextBox]::new()
        $t.Location=[Drawing.Point]::new(180,($Y - 2))
        $t.Size=[Drawing.Size]::new(330,24)
        $t.Text=$Value
        $form.Controls.Add($t)
        return $t
    }

    Add-Label 'Bot token' 95 | Out-Null
    $token=Add-Text 95 $existingToken
    $token.UseSystemPasswordChar=$true
    Add-Label 'Channel ID' 135 | Out-Null
    $channel=Add-Text 135 (Ini-Value $ini 'Remote' 'ChannelID' '')
    Add-Label 'Allowed user ID' 175 | Out-Null
    $user=Add-Text 175 (Ini-Value $ini 'Remote' 'UserID' '')
    Add-Label 'Poll interval (sec)' 215 | Out-Null
    $poll=Add-Text 215 (Ini-Value $ini 'Remote' 'PollSeconds' '4')

    $enabled=[Windows.Forms.CheckBox]::new()
    $enabled.Text='Enable Discord remote'
    $enabled.Location=[Drawing.Point]::new(180,254)
    $enabled.AutoSize=$true
    $enabled.Checked=(Ini-Value $ini 'Remote' 'Enabled' '0') -eq '1'
    $form.Controls.Add($enabled)

    $hint=[Windows.Forms.Label]::new()
    $hint.Text="Bot permissions: View Channel, Send Messages, Read Message History, Attach Files.`r`nEnable Message Content Intent. Only the configured user/channel can issue commands."
    $hint.Location=[Drawing.Point]::new(26,292)
    $hint.Size=[Drawing.Size]::new(484,52)
    $hint.ForeColor=[Drawing.Color]::DarkGray
    $form.Controls.Add($hint)

    $status=[Windows.Forms.Label]::new()
    $status.Text='Ready.'
    $status.Location=[Drawing.Point]::new(150,369)
    $status.Size=[Drawing.Size]::new(205,28)
    $status.ForeColor=[Drawing.Color]::Silver
    $form.Controls.Add($status)

    $test=[Windows.Forms.Button]::new()
    $test.Text='Test bot'
    $test.Location=[Drawing.Point]::new(26,360)
    $test.Size=[Drawing.Size]::new(110,32)
    $form.Controls.Add($test)

    $save=[Windows.Forms.Button]::new()
    $save.Text='Save + Start'
    $save.Location=[Drawing.Point]::new(370,360)
    $save.Size=[Drawing.Size]::new(140,32)
    $form.Controls.Add($save)

    $test.Add_Click({
        try {
            $status.Text='Testing...'
            if(!$token.Text.Trim() -or !$channel.Text.Trim()){ throw 'Token and Channel ID are required.' }
            if($channel.Text.Trim() -notmatch '^\d{15,22}$'){ throw 'Channel ID must be the numeric Discord channel ID.' }
            Send-Test $token.Text.Trim() $channel.Text.Trim()
            $status.Text='Connected.'
            [Windows.Forms.MessageBox]::Show('Test message sent successfully.','Strategy Lab Remote',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            $status.Text='Test failed.'
            Log ('ERROR bot test: ' + $_.Exception.Message)
            [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Bot test failed',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $save.Add_Click({
        try {
            if($enabled.Checked -and (!$token.Text.Trim() -or !$channel.Text.Trim() -or !$user.Text.Trim())){ throw 'Token, Channel ID and Allowed User ID are required when remote is enabled.' }
            if($channel.Text.Trim() -and $channel.Text.Trim() -notmatch '^\d{15,22}$'){ throw 'Channel ID must be numeric.' }
            if($user.Text.Trim() -and $user.Text.Trim() -notmatch '^\d{15,22}$'){ throw 'Allowed user ID must be numeric.' }
            $p=4
            if([int]::TryParse($poll.Text.Trim(),[ref]$p) -eq $false){ throw 'Poll interval must be a number.' }
            $p=[Math]::Max(2,[Math]::Min(30,$p))
            Save-Config $enabled.Checked $token.Text.Trim() $channel.Text.Trim() $user.Text.Trim() $p
            if($enabled.Checked) { Start-DiscordWorker }
            [Windows.Forms.MessageBox]::Show('Remote settings saved.','Strategy Lab Remote',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            $form.Close()
        } catch {
            Log ('ERROR save/start: ' + $_.Exception.Message)
            [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Could not save',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $form.Add_Shown({ $form.Activate(); $form.BringToFront() })
    Log ('INFO remote settings UI opened from ' + $InstallDir)
    [void]$form.ShowDialog()
    Log 'INFO remote settings UI closed.'
} catch {
    Log ('FATAL remote settings startup: ' + $_.Exception.ToString())
    Show-Fatal $_.Exception.Message
    exit 10
}
