<#
.SYNOPSIS
  Signs an unsigned .hap as an OpenHarmony *system app* (apl: system_core,
  app-feature: hos_system_app).

.DESCRIPTION
  Uses only the PUBLIC OpenHarmony test signing material that ships with every
  OpenHarmony SDK (toolchains/lib/OpenHarmony.p12, default password 123456 per
  the official hapsigner guide) plus rootCA.cer/subCA.cer from
  developtools_hapsigner/autosign/result (copied into ../signing).
  Stock OpenHarmony / Oniro images trust these certificates; commercial
  HarmonyOS does not, so the result installs only on OpenHarmony-based devices.

  Steps (see docs/application-dev/security/hapsigntool-guidelines.md):
    1. generate an app key pair (once; kept in .signing/ so reinstalls keep the same appId)
    2. issue an app certificate from "openharmony application ca"
    3. fill signing/profile-template.json (bundle name, cert, validity) and sign it
    4. sign the .hap
#>
param(
    [string]$InHap,
    [string]$OutHap,
    [string]$SdkLib,
    [string]$Java,
    # Only create key, certificate, profile and the IDE signing config (no hap needed).
    [switch]$PrepareOnly,
    [string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio'
)
if (-not $PrepareOnly -and -not $InHap) { throw 'pass -InHap <unsigned.hap> or -PrepareOnly' }
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $root '.signing'
New-Item -ItemType Directory -Force $work | Out-Null

if (-not $SdkLib) {
    $candidates = @(
        $(if ($env:OHOS_SDK_HOME) { Join-Path $env:OHOS_SDK_HOME '20\toolchains\lib' }),
        (Join-Path $env:LOCALAPPDATA 'OpenHarmony\Sdk\20\toolchains\lib'),
        'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib'
    ) | Where-Object { $_ -and (Test-Path (Join-Path $_ 'hap-sign-tool.jar')) }
    if (-not $candidates) { throw 'hap-sign-tool.jar not found; pass -SdkLib <sdk>/toolchains/lib' }
    $SdkLib = @($candidates)[0]
}
if (-not $Java) {
    $Java = @(
        $(if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\java.exe' }),
        'C:\Program Files\Huawei\DevEco Studio\jbr\bin\java.exe'
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $Java) { throw 'java.exe not found; set JAVA_HOME or pass -Java' }
}
if ($InHap -and -not $OutHap) { $OutHap = $InHap -replace '-unsigned\.hap$', '-signed.hap' }
if ($InHap -and $OutHap -eq $InHap) { $OutHap = $InHap -replace '\.hap$', '-signed.hap' }

$jar = Join-Path $SdkLib 'hap-sign-tool.jar'
$ks = Join-Path $work 'keystore.p12'
$chain = Join-Path $work 'app-chain.pem'
$profileJson = Join-Path $work 'profile.json'
$profileP7b = Join-Path $work 'profile.p7b'
# Public default passwords of the OpenHarmony test keystore -- not secrets.
$ksPass = '123456'
$alias = 'phoneagent-app'

function Invoke-SignTool([string[]]$toolArgs) {
    # java logs to stderr; don't let PowerShell 5.1 treat that as a terminating error
    $ErrorActionPreference = 'Continue'
    & $Java -jar $jar @toolArgs 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { throw "hap-sign-tool $($toolArgs[0]) failed (exit $LASTEXITCODE)" }
}

if (-not (Test-Path $ks)) {
    Copy-Item (Join-Path $SdkLib 'OpenHarmony.p12') $ks
    Invoke-SignTool @('generate-keypair', '-keyAlias', $alias, '-keyAlg', 'ECC', '-keySize', 'NIST-P-256',
        '-keystoreFile', $ks, '-keyPwd', $ksPass, '-keystorePwd', $ksPass)
    Remove-Item -ErrorAction SilentlyContinue $chain
}
if (-not (Test-Path $chain)) {
    Invoke-SignTool @('generate-app-cert', '-keyAlias', $alias, '-signAlg', 'SHA256withECDSA',
        '-issuer', 'C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN= OpenHarmony Application CA',
        '-issuerKeyAlias', 'openharmony application ca',
        '-subject', 'C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application Release',
        '-keystoreFile', $ks, '-subCaCertFile', (Join-Path $root 'signing\subCA.cer'),
        '-rootCaCertFile', (Join-Path $root 'signing\rootCA.cer'), '-outForm', 'certChain',
        '-outFile', $chain, '-keyPwd', $ksPass, '-keystorePwd', $ksPass, '-issuerKeyPwd', $ksPass, '-validity', '3650')
}

# Profile: our leaf cert must be the distribution certificate.
$leaf = [regex]::Match((Get-Content $chain -Raw), '-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----').Value
$leaf = ($leaf -replace "`r", '') + "`n"
$appJson = Get-Content (Join-Path $root 'AppScope\app.json5') -Raw
$bundle = [regex]::Match($appJson, '"bundleName"\s*:\s*"([^"]+)"').Groups[1].Value
if (-not $bundle) { throw 'bundleName not found in AppScope/app.json5' }

$profile = Get-Content (Join-Path $root 'signing\profile-template.json') -Raw | ConvertFrom-Json
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$profile.validity.'not-before' = $now - 86400
$profile.validity.'not-after' = $now + 10 * 365 * 86400
$profile.'bundle-info'.'distribution-certificate' = $leaf
$profile.'bundle-info'.'bundle-name' = $bundle
[IO.File]::WriteAllText($profileJson, ($profile | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))

Invoke-SignTool @('sign-profile', '-keyAlias', 'openharmony application profile release', '-signAlg', 'SHA256withECDSA',
    '-mode', 'localSign', '-profileCertFile', (Join-Path $SdkLib 'OpenHarmonyProfileRelease.pem'),
    '-inFile', $profileJson, '-keystoreFile', $ks, '-outFile', $profileP7b, '-keyPwd', $ksPass, '-keystorePwd', $ksPass)

# Same material for hvigor, so DevEco Studio builds are signed too (see hvigorfile.ts).
& (Join-Path $DevEco 'tools\node\node.exe') (Join-Path $PSScriptRoot 'ide-signing.js') $work $ksPass $alias
if ($LASTEXITCODE -ne 0) { throw 'ide-signing.js failed' }
if ($PrepareOnly) {
    Write-Host "Signing material ready in $work ($bundle, apl=system_core)"
    return
}

Invoke-SignTool @('sign-app', '-keyAlias', $alias, '-signAlg', 'SHA256withECDSA', '-mode', 'localSign',
    '-appCertFile', $chain, '-profileFile', $profileP7b, '-inFile', $InHap, '-keystoreFile', $ks,
    '-outFile', $OutHap, '-keyPwd', $ksPass, '-keystorePwd', $ksPass)

Write-Host "Signed ($bundle, apl=system_core): $OutHap"
