<#
.SYNOPSIS
  Boots the Oniro emulator (OpenHarmony 6.1 in QEMU for Windows, accelerated by the
  Windows Hypervisor Platform) if it is not running, connects hdc and waits until
  OpenHarmony has finished booting. Afterwards the emulator shows up as device
  127.0.0.1:55555 in DevEco Studio and in `hdc list targets`. -Stop shuts it down.
  Same QEMU setup as run.sh from the Oniro release, without needing bash.
  Registered in DevEco Studio as External Tool "Start Oniro emulator".
#>
param(
    [string]$Images = (Join-Path $env:USERPROFILE 'oniro\images'),
    [string]$Qemu = 'C:\Program Files\qemu',
    [string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio',
    [string]$Target = '127.0.0.1:55555',
    [string]$Accel = 'whpx',
    [string]$Cpu = 'host',    # the default qemu64 CPU makes OpenHarmony's foundation service crash at boot
    [switch]$Headless,    # no window (hdc only)
    [switch]$Foreground,  # run QEMU in this console and show its errors (troubleshooting)
    [switch]$Stop,
    [int]$TimeoutSec = 180
)
$ErrorActionPreference = 'Continue'
$hdc = Join-Path $DevEco 'sdk\default\openharmony\toolchains\hdc.exe'
$serialLog = Join-Path $env:TEMP 'oniro-emulator-serial.log'
$fwdHost, $fwdPort = $Target -split ':'

function Test-Booted {
    $out = (& $hdc -t $Target shell 'param get bootevent.boot.completed' 2>$null) -join ''
    return $out.Trim() -eq 'true'
}

# QEMU processes started by this script, recognised by their -name
function Get-Emulator {
    Get-CimInstance Win32_Process -Filter "Name like 'qemu-system-x86_64%'" |
        Where-Object { $_.CommandLine -match '-name oniro' -and $_.CommandLine -match "hostfwd=tcp:${fwdHost}:${fwdPort}-" }
}

if ($Stop) {
    $emu = Get-Emulator
    if (-not $emu) { Write-Host 'Emulator is not running'; exit 0 }
    & $hdc tconn $Target | Out-Null
    & $hdc -t $Target shell 'reboot shutdown' 2>$null | Out-Null   # clean shutdown, QEMU exits at power-off
    foreach ($i in 1..12) {
        Start-Sleep -Seconds 5
        if (-not (Get-Emulator)) { Write-Host 'Emulator stopped'; exit 0 }
    }
    $emu | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Write-Host 'Emulator did not shut down within 60 s; QEMU killed'
    exit 0
}

& $hdc tconn $Target | Out-Null
if (Test-Booted) {
    Write-Host "Emulator already running and connected: $Target"
    exit 0
}

# ---- QEMU command line (as in run.sh, Windows branch) ----
$qemuArgs = @(
    '-name', 'oniro',
    '-machine', 'q35', '-accel', $Accel, '-cpu', $Cpu, '-smp', '6', '-m', '4096M', '-boot', 'c',
    '-vga', 'none', '-device', 'virtio-gpu-pci,xres=360,yres=720,max_outputs=1,addr=08.0',
    '-display', $(if ($Headless) { 'none' } else { 'sdl,gl=off' }),
    '-rtc', 'base=utc,clock=host',
    '-device', 'es1370',
    '-initrd', 'ramdisk.img', '-kernel', 'bzImage',
    '-drive', 'if=none,file=updater.img,format=raw,id=updater,index=0', '-device', 'virtio-blk-pci,drive=updater',
    '-drive', 'if=none,file=system.img,format=raw,id=system,index=1', '-device', 'virtio-blk-pci,drive=system',
    '-drive', 'if=none,file=vendor.img,format=raw,id=vendor,index=2', '-device', 'virtio-blk-pci,drive=vendor',
    '-drive', 'if=none,file=userdata.img,format=raw,id=userdata,index=3', '-device', 'virtio-blk-pci,drive=userdata',
    '-serial', "file:$serialLog",
    '-append', ('ip=dhcp loglevel=4 console=ttyS0,115200 init=init root=/dev/ram0 rw ohos.boot.hardware=x86_general ' +
        'ohos.required_mount.system=/dev/block/vdb@/usr@ext4@ro,barrier=1@wait,required ' +
        'ohos.required_mount.vendor=/dev/block/vdc@/vendor@ext4@ro,barrier=1@wait,required ' +
        'ohos.required_mount.misc=/dev/block/vda@/misc@none@none=@wait,required'),
    '-netdev', "user,id=net0,hostfwd=tcp:${fwdHost}:${fwdPort}-:55555", '-device', 'virtio-net-pci,netdev=net0'
)

if (-not (Get-Emulator)) {
    # ---- checks with a hint for each missing piece of the setup (README) ----
    $missing = 'bzImage', 'ramdisk.img', 'updater.img', 'system.img', 'vendor.img', 'userdata.img' |
        Where-Object { -not (Test-Path (Join-Path $Images $_)) }
    if ($missing) {
        Write-Host "Emulator images not found in $Images (missing: $($missing -join ', '))."
        Write-Host 'Download and unpack oniro_emulator.zip (README, Setup), or pass -Images <folder>.'
        exit 1
    }
    $qemuExe = Join-Path $Qemu 'qemu-system-x86_64.exe'
    if (-not (Test-Path $qemuExe)) {
        $onPath = Get-Command qemu-system-x86_64.exe -ErrorAction SilentlyContinue
        if (-not $onPath) {
            Write-Host "QEMU not found in $Qemu. Install it: winget install SoftwareFreedomConservancy.QEMU (or pass -Qemu <folder>)."
            exit 1
        }
        $qemuExe = $onPath.Source
    }
    if (Get-NetTCPConnection -LocalPort $fwdPort -State Listen -ErrorAction SilentlyContinue) {
        Write-Host "Port $fwdPort is already in use, so hdc could not reach the emulator."
        Write-Host 'Close whatever uses it (e.g. an emulator started another way; for WSL: wsl --shutdown) and retry.'
        exit 1
    }

    if ($Foreground) {
        Write-Host "Running $qemuExe in this console (Ctrl+C stops it)..."
        Push-Location $Images
        & $qemuExe @qemuArgs
        Pop-Location
        exit $LASTEXITCODE
    }

    # The window variant (...w.exe) has no console. It is started through WMI, so it is not a child of
    # this script: closing or re-running DevEco's External Tool (or any shell) can't take it down with
    # its process tree, and nothing waits on its output.
    $qemuW = $qemuExe -replace '\.exe$', 'w.exe'
    $argLine = ($qemuArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    Write-Host "Starting Oniro emulator ($Images)..."
    Remove-Item $serialLog -ErrorAction SilentlyContinue
    $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = "`"$qemuW`" $argLine"; CurrentDirectory = $Images
    }
    if ($created.ReturnValue -ne 0) {
        Write-Host "Could not start QEMU (Win32_Process.Create returned $($created.ReturnValue))."
        exit 1
    }
    $proc = Get-Process -Id $created.ProcessId -ErrorAction SilentlyContinue
} else {
    Write-Host 'Emulator process already started, waiting for boot...'
    $proc = $null
}

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    if ($proc -and $proc.HasExited) {
        Write-Host "QEMU exited (code $($proc.ExitCode)). To see its error, run: .\scripts\start-emulator.ps1 -Foreground"
        Write-Host 'If it says WHPX is not available: enable "Windows Hypervisor Platform" (README, Setup) and reboot.'
        exit 1
    }
    & $hdc tconn $Target | Out-Null
    if (Test-Booted) {
        Write-Host "Emulator booted and connected: $Target"
        exit 0
    }
    Write-Host '  waiting for boot...'
}
Write-Host "Emulator did not finish booting within $TimeoutSec s. Last lines of the boot log ($serialLog):"
Get-Content $serialLog -Tail 15 -ErrorAction SilentlyContinue
exit 1
