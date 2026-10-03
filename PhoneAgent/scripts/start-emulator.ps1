<#
.SYNOPSIS
  Boots the Oniro emulator (WSL2 + KVM, see emulator.sh) if it is not running,
  connects hdc and waits until OpenHarmony has finished booting. Afterwards the
  emulator shows up as device 127.0.0.1:55555 in DevEco Studio and in `hdc list targets`.
  Registered in DevEco Studio as External Tool "Start Oniro emulator".
#>
param(
    [string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio',
    [string]$Target = '127.0.0.1:55555',
    [string]$Distro = 'Ubuntu-24.04',
    [int]$TimeoutSec = 180
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$hdc = Join-Path $DevEco 'sdk\default\openharmony\toolchains\hdc.exe'

function Test-Booted {
    $out = (& $hdc -t $Target shell 'param get bootevent.boot.completed' 2>$null) -join ''
    return $out.Trim() -eq 'true'
}

& $hdc tconn $Target | Out-Null
if (Test-Booted) {
    Write-Host "Emulator already running and connected: $Target"
    exit 0
}

# emulator.sh lives in the repo; WSL sees the Windows path under /mnt/<drive>/...
$wslScript = (& wsl.exe -d $Distro -- wslpath -a ($root -replace '\\', '/')).Trim() + '/scripts/emulator.sh'
Write-Host "Starting Oniro emulator in WSL ($Distro)..."
& wsl.exe -d $Distro -u root -- bash $wslScript start

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    & $hdc tconn $Target | Out-Null
    if (Test-Booted) {
        Write-Host "Emulator booted and connected: $Target"
        exit 0
    }
    Write-Host '  waiting for boot...'
}
Write-Host "Emulator did not finish booting within $TimeoutSec s"
exit 1
