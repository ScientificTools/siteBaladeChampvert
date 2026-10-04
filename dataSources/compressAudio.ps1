param(
    [string]$Bitrate = '128k',
    [string]$Destination = 'compressedSounds'
)

$ErrorActionPreference = 'Stop'

$ffmpeg = Join-Path $PSScriptRoot 'ffmpeg.exe'
$src    = Join-Path $PSScriptRoot 'sounds'
$dst    = Join-Path $PSScriptRoot $Destination
$exts   = '.mp3', '.wav', '.m4a', '.flac', '.ogg', '.aac', '.wma', '.aif', '.aiff', '.opus'

New-Item -ItemType Directory -Force -Path $dst | Out-Null

Get-ChildItem -Path $src -File | Where-Object { $exts -contains $_.Extension.ToLower() } | ForEach-Object {
    $out = Join-Path $dst ($_.BaseName + '.m4a')
    Write-Host "Compression : $($_.Name)"
    & $ffmpeg -y -hide_banner -loglevel error -i $_.FullName -vn -c:a aac -b:a $Bitrate $out
    if ($LASTEXITCODE -ne 0) { Write-Warning "Échec : $($_.Name)" }
}

Write-Host 'Terminé.'
