$ErrorActionPreference='Stop'
$demoHdc='C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
$demoHelper=Join-Path $PSScriptRoot 'demo-ui.ps1'
$demoMappings=@(@('Dziadek','Grandpa'),@('Kuba','Jacob'),@('Mama','Mom'),@('Tata','Dad'))
foreach($demoMapping in $demoMappings) {
  & $demoHdc -t 127.0.0.1:55555 shell uitest uiInput swipe 170 280 170 595 600 | Out-Null
  Start-Sleep -Milliseconds 700
  $demoRows=(& $demoHelper list -Bundle com.ohos.contacts) | ConvertFrom-Json
  if(!($demoRows | Where-Object {$_.text -eq $demoMapping[0]})) {
    & $demoHdc -t 127.0.0.1:55555 shell uitest uiInput swipe 170 570 170 250 600 | Out-Null
    Start-Sleep -Milliseconds 700
  }
  & $demoHelper click $demoMapping[0] -Bundle com.ohos.contacts -MatchText
  & $demoHelper click edits -Bundle com.ohos.contacts -MatchText
  & $demoHelper replace $demoMapping[0] $demoMapping[1] -Bundle com.ohos.contacts -MatchText
  & $demoHelper click AddContact_OK -Bundle com.ohos.contacts
  $demoSaved=(& $demoHelper list -Bundle com.ohos.contacts) | ConvertFrom-Json
  if(!($demoSaved | Where-Object {$_.text -eq $demoMapping[1]})) { throw "Rename not confirmed: $($demoMapping[1])" }
  Write-Output "Renamed $($demoMapping[0]) to $($demoMapping[1]); phone number preserved."
  & $demoHdc -t 127.0.0.1:55555 shell uitest uiInput keyEvent Back | Out-Null
  Start-Sleep -Milliseconds 1000
}
