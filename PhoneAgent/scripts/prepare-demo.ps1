<# Refreshes the presentation note for tomorrow and checks every required app. Build apps first. #>
param(
    [string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio',
    [string]$Target = '127.0.0.1:55555'
)
$ErrorActionPreference = 'Stop'
$demoHdc = Join-Path $DevEco 'sdk\default\openharmony\toolchains\hdc.exe'
$demoApps = @{
    'Oniro Agent' = 'com.hackyeah.phoneagent'; 'Notes' = 'com.hackyeah.notes';
    'Calendar' = 'com.hackyeah.calendar'; 'Reminders' = 'com.hackyeah.reminders';
    'Contacts' = 'com.ohos.contacts'; 'Messages' = 'com.ohos.mms'
}
foreach ($demoApp in $demoApps.GetEnumerator()) {
    $demoInstalled = (& $demoHdc -t $Target shell "bm dump -n $($demoApp.Value)") -join "`n"
    if ($demoInstalled -notmatch [regex]::Escape($demoApp.Value)) {
        throw "$($demoApp.Key) is not installed ($($demoApp.Value)). Follow README Setup first."
    }
    Write-Host "$($demoApp.Key): installed"
}
$demoSeed = (& $demoHdc -t $Target shell 'aa start -a EntryAbility -b com.hackyeah.notes --pb prepareDemo true') -join "`n"
if ($demoSeed -notmatch 'start ability successfully') { throw "Could not prepare Notes: $demoSeed" }
Write-Host 'Notes opened. Check Grandma birthday party: tomorrow at 17:00, gift reminder at 10:00.'
Write-Host 'Confirm Grandma exists in Contacts. This script preserves contacts, calendar events and reminders.'
Write-Host 'Before a repeat presentation, remove only the previous demo event/reminder using their Delete buttons.'
