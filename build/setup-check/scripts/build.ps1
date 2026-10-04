<#
.SYNOPSIS
  Build -> sign as system app -> install -> launch PhoneAgent on an OpenHarmony
  device/emulator reachable over hdc.

.EXAMPLE
  .\scripts\build.ps1                 # build, sign, install, launch
  .\scripts\build.ps1 -NoInstall      # build + sign only (output: build\phoneagent-signed.hap)
  .\scripts\build.ps1 -Release -NoInstall   # release build for distribution (debug-only test hooks off)
#>
param(
    [switch]$NoInstall,
    [switch]$Release,
    [string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio',
    # Folder that contains the API 20 *full* OpenHarmony SDK in a "20" subfolder.
    [string]$Sdk = $(if ($env:OHOS_BASE_SDK_HOME) { $env:OHOS_BASE_SDK_HOME } else { Join-Path $env:LOCALAPPDATA 'OpenHarmony\Sdk' }),
    [string]$Target = '127.0.0.1:55555'
)
# Native tools write progress to stderr; PowerShell 5.1 would turn that into
# terminating errors under 'Stop', so we check exit codes explicitly instead.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot

$env:NODE_HOME = Join-Path $DevEco 'tools\node'
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = Join-Path $DevEco 'jbr' }
# hvigorw/ohpm/packing tools spawn plain node.exe / java.exe from PATH
$env:Path = "$env:NODE_HOME;$env:JAVA_HOME\bin;$env:Path"
$env:OHOS_BASE_SDK_HOME = $Sdk
$hdc = Join-Path $DevEco 'sdk\default\openharmony\toolchains\hdc.exe'
$bundle = [regex]::Match((Get-Content (Join-Path $root 'AppScope\app.json5') -Raw), '"bundleName"\s*:\s*"([^"]+)"').Groups[1].Value

Push-Location $root
try {
    if (-not (Test-Path (Join-Path $root 'oh_modules'))) {
        cmd /c "`"$DevEco\tools\ohpm\bin\ohpm.bat`" install 2>&1"
        if ($LASTEXITCODE -ne 0) { throw "ohpm install failed ($LASTEXITCODE)" }
    }
    $buildMode = if ($Release) { 'release' } else { 'debug' }
    cmd /c "node.exe `"$DevEco\tools\hvigor\bin\hvigorw.js`" --mode module -p product=default -p module=entry@default -p buildMode=$buildMode assembleHap --no-daemon 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "hvigor build failed ($LASTEXITCODE)" }
} finally {
    Pop-Location
}

$unsigned = Join-Path $root 'entry\build\default\outputs\default\entry-default-unsigned.hap'
$outDir = Join-Path $root 'build'
New-Item -ItemType Directory -Force $outDir | Out-Null
$signed = Join-Path $outDir $(if ($Release) { 'phoneagent-release-signed.hap' } else { 'phoneagent-signed.hap' })
& (Join-Path $PSScriptRoot 'sign.ps1') -InHap $unsigned -OutHap $signed -SdkLib (Join-Path $Sdk '20\toolchains\lib') -Java "$env:JAVA_HOME\bin\java.exe"
if (-not $?) { throw 'signing failed' }

if ($NoInstall) { return }
# hdc exits 0 even when installation fails, so check its output.
$installOut = (& $hdc -t $Target install -r $signed) -join "`n"
Write-Host $installOut
if ($installOut -notmatch 'install bundle successfully') { throw 'hdc install failed' }
& $hdc -t $Target shell aa start -a EntryAbility -b $bundle
