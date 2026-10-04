<#
.SYNOPSIS
  Builds the app + instrumented test HAP, signs both, installs them on the
  emulator/device and runs the hypium test suite there (aa test).

.EXAMPLE
  .\scripts\test.ps1
#>
param(
    [string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio',
    [string]$Sdk = $(if ($env:OHOS_BASE_SDK_HOME) { $env:OHOS_BASE_SDK_HOME } else { Join-Path $env:LOCALAPPDATA 'OpenHarmony\Sdk' }),
    [string]$Target = '127.0.0.1:55555'
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$hdc = Join-Path $DevEco 'sdk\default\openharmony\toolchains\hdc.exe'

# 1. app hap (build + sign, no install/launch)
& (Join-Path $PSScriptRoot 'build.ps1') -NoInstall -DevEco $DevEco -Sdk $Sdk
if (-not $?) { throw 'app build failed' }

# 2. test hap
$env:NODE_HOME = Join-Path $DevEco 'tools\node'
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = Join-Path $DevEco 'jbr' }
$env:Path = "$env:NODE_HOME;$env:JAVA_HOME\bin;$env:Path"
$env:OHOS_BASE_SDK_HOME = $Sdk
Push-Location $root
try {
    cmd /c "node.exe `"$DevEco\tools\hvigor\bin\hvigorw.js`" --mode module -p product=default -p module=entry@ohosTest assembleHap --no-daemon 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "test hap build failed ($LASTEXITCODE)" }
} finally {
    Pop-Location
}
$testUnsigned = Join-Path $root 'entry\build\default\outputs\ohosTest\entry-ohosTest-unsigned.hap'
$testSigned = Join-Path $root 'build\phoneagent-test-signed.hap'
& (Join-Path $PSScriptRoot 'sign.ps1') -DevEco $DevEco -InHap $testUnsigned -OutHap $testSigned -SdkLib (Join-Path $Sdk '20\toolchains\lib') -Java "$env:JAVA_HOME\bin\java.exe"
if (-not $?) { throw 'test hap signing failed' }

# 3. install both and run
$installOut = (& $hdc -t $Target install -r (Join-Path $root 'build\phoneagent-signed.hap') $testSigned) -join "`n"
Write-Host $installOut
if ($installOut -notmatch 'install bundle successfully') { throw 'hdc install failed' }

$bundle = [regex]::Match((Get-Content (Join-Path $root 'AppScope\app.json5') -Raw), '"bundleName"\s*:\s*"([^"]+)"').Groups[1].Value
$out = (& $hdc -t $Target shell "aa test -b $bundle -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 30000") -join "`n"
# print failing test details (non-empty stream=) and the summary only
$out -split "`n" | Where-Object { $_ -match 'stream=\S|OHOS_REPORT_STATUS: test=|OHOS_REPORT_STATUS_CODE: -' } |
    Where-Object { $_ -notmatch 'OHOS_REPORT_STATUS: test=' -or $_ -match 'stream=\S' } | ForEach-Object { Write-Host $_ }
$summary = [regex]::Match($out, 'Tests run: (\d+), Failure: (\d+), Error: (\d+), Pass: (\d+)')
if (-not $summary.Success) { throw 'no test summary found in aa test output' }
if ([int]$summary.Groups[2].Value -gt 0 -or [int]$summary.Groups[3].Value -gt 0) { throw "tests failed: $($summary.Value)" }
Write-Host "ALL TESTS PASSED: $($summary.Value)"
