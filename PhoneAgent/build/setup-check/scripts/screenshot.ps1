<#
.SYNOPSIS
  Saves a screenshot of the emulator/device to build\shots\<Name>.jpeg.
.EXAMPLE
  .\scripts\screenshot.ps1 -Name main-light
#>
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio',
    [string]$Target = '127.0.0.1:55555'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$hdc = Join-Path $DevEco 'sdk\default\openharmony\toolchains\hdc.exe'
$dir = Join-Path $root 'build\shots'
New-Item -ItemType Directory -Force $dir | Out-Null
$remote = '/data/local/tmp/oa-shot.jpeg'
& $hdc -t $Target shell "snapshot_display -f $remote" | Out-Null
& $hdc -t $Target file recv $remote (Join-Path $dir "$Name.jpeg") | Out-Null
Write-Host (Join-Path $dir "$Name.jpeg")
