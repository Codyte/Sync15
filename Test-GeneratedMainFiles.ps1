[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$FlowRoot
)
$ErrorActionPreference = 'Stop'

if(-not (Test-Path $FlowRoot)){ throw "FlowRoot not found: $FlowRoot" }

$menuRoot = Join-Path $FlowRoot 'menu'
if(-not (Test-Path $menuRoot)){ throw "menu root not found: $menuRoot" }

$allMain = @(Get-ChildItem -Path $menuRoot -Filter 'main.ps1' -Recurse -File)
$wrapperFiles = @()
foreach($f in $allMain){
  $txt = Get-Content -Path $f.FullName -Raw
  if($txt -match 'function\s+Invoke-FlowAction-'){ $wrapperFiles += [pscustomobject]@{Path=$f.FullName;Text=$txt} }
}

foreach($wf in $wrapperFiles){
  $t = $wf.Text
  if($t -match "(?m)^\s*'Write-Host"){ throw "Wrapper body as single-quoted string: $($wf.Path)" }
  if($t -match '(?m)^\s*"Write-Host'){ throw "Wrapper body as double-quoted string: $($wf.Path)" }
  if($t -match "(?m)^\s*@'"){ throw "Wrapper body uses here-string start @': $($wf.Path)" }
  if($t -match "(?m)^\s*'@"){ throw "Wrapper body uses here-string end '@: $($wf.Path)" }
}

function Require-MainByFunction([string]$base,[string]$functionName){
  $x = Get-ChildItem -Path $base -Recurse -Filter 'main.ps1' -File | Where-Object {
    (Get-Content -Path $_.FullName -Raw) -match ("function\s+" + [regex]::Escape($functionName) + "\b")
  } | Select-Object -First 1
  if($null -eq $x){ throw "Expected wrapper function not found: $functionName" }
  return $x.FullName
}

$p1 = Require-MainByFunction -base $menuRoot -functionName 'Invoke-FlowAction-MenuLimpezaDisco-Op-1'
$t1 = Get-Content -Path $p1 -Raw
if($t1 -notmatch 'function\s+Invoke-FlowAction-MenuLimpezaDisco-Op-1'){ throw "Missing wrapper function in $p1" }
if($t1 -notmatch 'Write-Host\s+"Iniciando Limpeza de Disco'){ throw "Missing expected Write-Host in $p1" }
if($t1 -notmatch 'Start-Process\s+"cleanmgr\.exe"'){ throw "Missing cleanmgr call in $p1" }
if($t1 -notmatch 'Pause-Script'){ throw "Missing Pause-Script in $p1" }
if($t1 -match "(?m)^\s*'Write-Host"){ throw "Quoted code found in $p1" }
if($t1 -match '(?m)^\s*@"' -or $t1 -match "(?m)^\s*@'"){ throw "Here-string found in $p1" }

$p2 = Require-MainByFunction -base $menuRoot -functionName 'Invoke-FlowAction-MenuLimpezaDisco-Op-2'
$t2 = Get-Content -Path $p2 -Raw
if($t2 -notmatch 'Start-Process\s+"dfrgui\.exe"'){ throw "Missing dfrgui in $p2" }

$p3 = Require-MainByFunction -base $menuRoot -functionName 'Invoke-FlowAction-MenuDesempenho-Op-1'
$t3 = Get-Content -Path $p3 -Raw
if($t3 -notmatch 'Start-Process\s+"taskmgr\.exe"'){ throw "Missing taskmgr in $p3" }

$p4 = Require-MainByFunction -base $menuRoot -functionName 'Invoke-FlowAction-MenuDesempenho-Op-6'
$t4 = Get-Content -Path $p4 -Raw
if($t4 -notmatch 'Start-Process\s+"ms-settings:display-advancedgraphics"'){ throw "Missing advanced graphics settings call in $p4" }

Write-Host "TEST-GENERATED-MAIN-FILES PASS"
