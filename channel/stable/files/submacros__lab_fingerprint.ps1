param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if (!(Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Input file does not exist: $InputPath"
}

$parent = Split-Path -Parent $OutputPath
if ($parent -and !(Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

$hash = (Get-FileHash -LiteralPath $InputPath -Algorithm SHA256).Hash
[IO.File]::WriteAllText($OutputPath, $hash, (New-Object Text.UTF8Encoding($false)))
