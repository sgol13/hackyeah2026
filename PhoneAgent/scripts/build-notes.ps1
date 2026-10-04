<# Builds and installs the separate Notes companion app. #>
param(
    [switch]$NoInstall,
    [string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio',
    [string]$Sdk = $(if ($env:OHOS_BASE_SDK_HOME) { $env:OHOS_BASE_SDK_HOME } else { Join-Path $env:LOCALAPPDATA 'OpenHarmony\Sdk' }),
    [string]$Target = '127.0.0.1:55555'
)
$ErrorActionPreference = 'Continue'
$agentRoot = Split-Path -Parent $PSScriptRoot
$notesRoot = Join-Path $agentRoot 'notes'
$env:NODE_HOME = Join-Path $DevEco 'tools\node'
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = Join-Path $DevEco 'jbr' }
$env:Path = "$env:NODE_HOME;$env:JAVA_HOME\bin;$env:Path"
$env:OHOS_BASE_SDK_HOME = $Sdk
Push-Location $notesRoot
try {
    # This project has no runtime dependencies.
    New-Item -ItemType Directory -Force 'oh_modules' | Out-Null
    & node.exe (Join-Path $DevEco 'tools\hvigor\bin\hvigorw.js') --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) { throw "Notes build failed ($LASTEXITCODE)" }
} finally { Pop-Location }
$signed = Join-Path $agentRoot 'build\notes-signed.hap'
New-Item -ItemType Directory -Force (Split-Path -Parent $signed) | Out-Null
& (Join-Path $PSScriptRoot 'sign.ps1') -ProjectRoot $notesRoot -InHap (Join-Path $notesRoot 'entry\build\default\outputs\default\entry-default-unsigned.hap') -OutHap $signed -SdkLib (Join-Path $Sdk '20\toolchains\lib') -Java "$env:JAVA_HOME\bin\java.exe"
if (-not $?) { throw 'Notes signing failed' }
if ($NoInstall) { return }
$hdc = Join-Path $DevEco 'sdk\default\openharmony\toolchains\hdc.exe'
$installOut = (& $hdc -t $Target install -r $signed) -join "`n"
Write-Host $installOut
if ($installOut -notmatch 'install bundle successfully') { throw 'Notes install failed' }
& $hdc -t $Target shell aa start -a EntryAbility -b com.hackyeah.notes
