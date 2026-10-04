param([string]$Action='list', [string]$Id='', [string]$Text='', [string]$Bundle='com.hackyeah.phoneagent', [switch]$MatchText, [string]$WithinText='' )
$ErrorActionPreference='Stop'
$skillsHdc='C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
& $skillsHdc -t 127.0.0.1:55555 shell uitest dumpLayout -p /data/local/tmp/skills-ui.json -b $Bundle | Out-Null
& $skillsHdc -t 127.0.0.1:55555 file recv /data/local/tmp/skills-ui.json "$PSScriptRoot/skills-ui.json" | Out-Null
$skillsTree=Get-Content "$PSScriptRoot/skills-ui.json" -Raw | ConvertFrom-Json
$skillsNodes=[System.Collections.Generic.List[object]]::new()
function Add-SkillNode($node) {
  $skillsNodes.Add($node.attributes)
  foreach($child in $node.children) { Add-SkillNode $child }
}
Add-SkillNode $skillsTree
if($Action -eq 'list') {
  $skillsNodes | Where-Object {$_.id -or $_.text} | Select-Object id,text,bounds,type,checked | ConvertTo-Json -Compress
  exit
}
$demoWithinPrefix=''
if($WithinText) { $demoWithinNode=$skillsNodes | Where-Object {$_.text -eq $WithinText} | Select-Object -First 1; if(!$demoWithinNode) { throw "Missing row: $WithinText" }; $demoWithinPrefix=$demoWithinNode.hierarchy.Substring(0,$demoWithinNode.hierarchy.LastIndexOf(',')) }
$skillsNode=$skillsNodes | Where-Object { ($MatchText -and $_.text -eq $Id) -or (-not $MatchText -and $_.id -eq $Id) } | Where-Object { !$WithinText -or $_.hierarchy.StartsWith($demoWithinPrefix + ',') } | Select-Object -First 1
if(!$skillsNode) { throw "Missing node: $Id" }
$skillsCoords=[regex]::Matches($skillsNode.bounds,'\d+') | ForEach-Object {[int]$_.Value}
$skillsX=[int](($skillsCoords[0]+$skillsCoords[2])/2)
$skillsY=[int](($skillsCoords[1]+$skillsCoords[3])/2)
if($Action -eq 'click') { & $skillsHdc -t 127.0.0.1:55555 shell uitest uiInput click $skillsX $skillsY }
elseif($Action -eq 'input') {
  if($Text.Contains("'")) { throw 'Use text without single quotes in this verification helper.' }
  & $skillsHdc -t 127.0.0.1:55555 shell "uitest uiInput inputText $skillsX $skillsY '$Text'"
}
elseif($Action -eq 'replace') {
  if($Text.Contains("'")) { throw 'Use text without single quotes in this verification helper.' }
  & $skillsHdc -t 127.0.0.1:55555 shell uitest uiInput click $skillsX $skillsY
  Start-Sleep -Milliseconds 500
  & $skillsHdc -t 127.0.0.1:55555 shell uitest uiInput keyEvent 2072 2017
  & $skillsHdc -t 127.0.0.1:55555 shell "uitest uiInput text '$Text'"
}
else { throw "Unknown action $Action" }
Start-Sleep -Milliseconds 1200
