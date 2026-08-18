param(
    [Parameter(Mandatory=$true)][string]$InstallDir
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
[Windows.Forms.Application]::EnableVisualStyles()

$root = Join-Path $env:APPDATA 'Ultimate_Macro\StrategyEditor'
$configPath = Join-Path $root 'remote.ini'
$workerPath = Join-Path $InstallDir 'submacros\lab_discord_worker.ps1'
$apiBase = 'https://discord.com/api/v10'
New-Item -ItemType Directory -Force -Path $root | Out-Null

function Read-Ini([string]$Path) {
    $result = @{}; if (!(Test-Path -LiteralPath $Path)) { return $result }; $section=''
    foreach ($raw in [IO.File]::ReadAllLines($Path)) {
        $line=$raw.Trim(); if(!$line -or $line.StartsWith(';') -or $line.StartsWith('#')){continue}
        if($line.StartsWith('[') -and $line.EndsWith(']')){$section=$line.Substring(1,$line.Length-2).Trim().ToLowerInvariant();if(!$result.ContainsKey($section)){$result[$section]=@{}};continue}
        $eq=$line.IndexOf('=');if($eq -gt 0 -and $section){$result[$section][$line.Substring(0,$eq).Trim().ToLowerInvariant()]=$line.Substring($eq+1).Trim()}
    }
    return $result
}
function Ini-Value($Data,[string]$Section,[string]$Key,[string]$Default=''){ $s=$Section.ToLowerInvariant();$k=$Key.ToLowerInvariant();if($Data.ContainsKey($s)-and $Data[$s].ContainsKey($k)){return [string]$Data[$s][$k]};return $Default }
function Protect-Token([string]$Token){$bytes=[Text.Encoding]::UTF8.GetBytes($Token);$p=[Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser);return [Convert]::ToBase64String($p)}
function Unprotect-Token([string]$Cipher){if(!$Cipher){return ''};try{$b=[Convert]::FromBase64String($Cipher);$p=[Security.Cryptography.ProtectedData]::Unprotect($b,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser);return [Text.Encoding]::UTF8.GetString($p)}catch{return ''}}
function Save-Config([bool]$Enabled,[string]$Token,[string]$Channel,[string]$User,[int]$Poll){
    $protected = Protect-Token $Token
    $text = "[Remote]`r`nEnabled=" + ($(if($Enabled){'1'}else{'0'})) + "`r`nChannelID=$Channel`r`nUserID=$User`r`nPollSeconds=$Poll`r`nTokenProtected=$protected`r`n"
    [IO.File]::WriteAllText($configPath,$text,(New-Object Text.UTF8Encoding($false)))
}
function Send-Test([string]$Token,[string]$Channel){
    $headers=@{Authorization=('Bot '+$Token);'User-Agent'='UltimateMacroStrategyLab/0.3'}
    $payload=@{content='✅ Ultimate Macro Strategy Lab remote is connected.';allowed_mentions=@{parse=@()}}|ConvertTo-Json -Depth 4 -Compress
    Invoke-RestMethod -Uri "$apiBase/channels/$Channel/messages" -Headers $headers -Method Post -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) | Out-Null
}

$ini=Read-Ini $configPath
$existingToken=Unprotect-Token (Ini-Value $ini 'Remote' 'TokenProtected' '')

$form=New-Object Windows.Forms.Form
$form.Text='Strategy Lab Remote'
$form.StartPosition='CenterScreen'
$form.ClientSize=New-Object Drawing.Size(520,420)
$form.BackColor=[Drawing.Color]::FromArgb(18,18,18)
$form.ForeColor=[Drawing.Color]::Gainsboro
$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false

$title=New-Object Windows.Forms.Label;$title.Text='Discord Remote';$title.Font=New-Object Drawing.Font('Segoe UI',16,[Drawing.FontStyle]::Bold);$title.ForeColor=[Drawing.Color]::FromArgb(85,183,255);$title.Location=New-Object Drawing.Point(24,18);$title.AutoSize=$true;$form.Controls.Add($title)
$sub=New-Object Windows.Forms.Label;$sub.Text='Private local controller • DPAPI-protected token • safe between-match switching';$sub.Location=New-Object Drawing.Point(26,55);$sub.AutoSize=$true;$sub.ForeColor=[Drawing.Color]::Gray;$form.Controls.Add($sub)

function Add-Label([string]$Text,[int]$Y){$l=New-Object Windows.Forms.Label;$l.Text=$Text;$l.Location=New-Object Drawing.Point(26,$Y);$l.Size=New-Object Drawing.Size(150,22);$form.Controls.Add($l);return $l}
function Add-Text([int]$Y,[string]$Value=''){$t=New-Object Windows.Forms.TextBox;$t.Location=New-Object Drawing.Point(180,$Y-2);$t.Size=New-Object Drawing.Size(310,24);$t.Text=$Value;$form.Controls.Add($t);return $t}

Add-Label 'Bot token' 95 | Out-Null;$token=Add-Text 95 $existingToken;$token.UseSystemPasswordChar=$true
Add-Label 'Channel ID' 135 | Out-Null;$channel=Add-Text 135 (Ini-Value $ini 'Remote' 'ChannelID' '')
Add-Label 'Allowed user ID' 175 | Out-Null;$user=Add-Text 175 (Ini-Value $ini 'Remote' 'UserID' '')
Add-Label 'Poll interval (sec)' 215 | Out-Null;$poll=Add-Text 215 (Ini-Value $ini 'Remote' 'PollSeconds' '4')

$enabled=New-Object Windows.Forms.CheckBox;$enabled.Text='Enable Discord remote';$enabled.Location=New-Object Drawing.Point(180,254);$enabled.AutoSize=$true;$enabled.Checked=(Ini-Value $ini 'Remote' 'Enabled' '0') -eq '1';$form.Controls.Add($enabled)
$hint=New-Object Windows.Forms.Label;$hint.Text="Required bot permissions: View Channel, Send Messages, Read Message History, Attach Files.`r`nEnable Message Content Intent in Discord Developer Portal. Never share your bot token.";$hint.Location=New-Object Drawing.Point(26,292);$hint.Size=New-Object Drawing.Size(464,52);$hint.ForeColor=[Drawing.Color]::DarkGray;$form.Controls.Add($hint)

$test=New-Object Windows.Forms.Button;$test.Text='Test bot';$test.Location=New-Object Drawing.Point(26,360);$test.Size=New-Object Drawing.Size(110,32);$form.Controls.Add($test)
$save=New-Object Windows.Forms.Button;$save.Text='Save + Start';$save.Location=New-Object Drawing.Point(350,360);$save.Size=New-Object Drawing.Size(140,32);$form.Controls.Add($save)

$test.Add_Click({
    try {
        if(!$token.Text.Trim() -or !$channel.Text.Trim()){throw 'Token and Channel ID are required.'}
        Send-Test $token.Text.Trim() $channel.Text.Trim()
        [Windows.Forms.MessageBox]::Show('Test message sent successfully.','Strategy Lab Remote','OK','Information') | Out-Null
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Bot test failed','OK','Error') | Out-Null }
})

$save.Add_Click({
    try {
        if($enabled.Checked -and (!$token.Text.Trim() -or !$channel.Text.Trim() -or !$user.Text.Trim())){throw 'Token, Channel ID and Allowed User ID are required when remote is enabled.'}
        $p=4;if([int]::TryParse($poll.Text.Trim(),[ref]$p) -eq $false){throw 'Poll interval must be a number.'};$p=[Math]::Max(2,[Math]::Min(30,$p))
        Save-Config $enabled.Checked $token.Text.Trim() $channel.Text.Trim() $user.Text.Trim() $p
        if($enabled.Checked -and (Test-Path -LiteralPath $workerPath)){Start-Process powershell.exe -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$workerPath,'-InstallDir',$InstallDir) -WindowStyle Hidden}
        [Windows.Forms.MessageBox]::Show('Remote settings saved.','Strategy Lab Remote','OK','Information') | Out-Null
        $form.Close()
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Could not save','OK','Error') | Out-Null }
})

[void]$form.ShowDialog()
