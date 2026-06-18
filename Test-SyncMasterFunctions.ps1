[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [switch]$RunSafeSmokeTests,
    [switch]$GenerateReports,
    [switch]$IncludeCallGraph,
    [switch]$VerboseReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-Set([string[]]$items){ $h=@{}; foreach($i in $items){ if($i){ $h[$i.ToLowerInvariant()]=$true } }; return $h }
function Has-AnyToken([string]$text,[string[]]$tokens){
    if([string]::IsNullOrWhiteSpace($text)){ return $false }
    $t = $text.ToLowerInvariant()
    foreach($k in $tokens){ if($t.Contains($k.ToLowerInvariant())){ return $true } }
    return $false
}
function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function To-JsonFile($obj,[string]$path){ $obj | ConvertTo-Json -Depth 12 | Set-Content -Path $path -Encoding UTF8 }

$dangerousTokens = @(
'remove-item','set-itemproperty','new-itemproperty','remove-itemproperty',
'stop-service','start-service','restart-service','set-service',
'start-process','invoke-expression','iex',
'bcdedit','fsutil','powercfg','schtasks','diskpart','format',
'robocopy','netsh','sfc','dism','chkdsk','winget','choco','reg.exe'
)
$licenseTokens = @('ativar-crack','crack','kms','slmgr','ospp','bypass','licenca','licença','product key','ativacao nao oficial','ativação não oficial')

try {
    $src = (Resolve-Path $SourcePath).Path
} catch {
    Write-Error "Source file not found: $SourcePath"
    exit 1
}
Ensure-Dir $OutputRoot

$tokens=$null; $errs=$null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src,[ref]$tokens,[ref]$errs)
if($errs -and @($errs).Count -gt 0){
    "Parser errors in source:" | Set-Content -Path (Join-Path $OutputRoot 'broken-functions.md') -Encoding UTF8
    $errs | ForEach-Object { "L$($_.Extent.StartLineNumber): $($_.Message)" } | Add-Content -Path (Join-Path $OutputRoot 'broken-functions.md')
    exit 1
}

$funcAsts = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
$funcNames = @{}
foreach($f in $funcAsts){ $funcNames[$f.Name.ToLowerInvariant()] = $true }

$allFunctions = New-Object System.Collections.Generic.List[object]
$brokenCalls = New-Object System.Collections.Generic.List[object]
$risky = New-Object System.Collections.Generic.List[object]
$sensitive = New-Object System.Collections.Generic.List[object]
$smoke = New-Object System.Collections.Generic.List[object]

foreach($f in $funcAsts){
    $name = $f.Name
    $text = $f.Extent.Text
    $paramBlock = $f.Parameters
    $params = @()
    $mandatory = @()
    if($paramBlock){
        foreach($p in $paramBlock){
            $pname = $p.Name.VariablePath.UserPath
            $params += $pname
            $ptext = $p.Extent.Text
            if($ptext -match 'Mandatory\s*=\s*\$true'){ $mandatory += $pname }
        }
    }

    $cmdAsts = @($f.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
    $calls = @()
    $dangerHits = @()
    foreach($c in $cmdAsts){
        $cn = $c.GetCommandName()
        if([string]::IsNullOrWhiteSpace($cn)){ continue }
        $calls += $cn
        if(Has-AnyToken $cn $dangerousTokens){ $dangerHits += $cn }
        if(($cn -ieq 'robocopy') -and ($c.Extent.Text -match '/MIR|/MOVE|/PURGE')){ $dangerHits += 'robocopy-destructive-flags' }
    }
    $calls = @($calls | Sort-Object -Unique)
    $dangerHits = @($dangerHits | Sort-Object -Unique)

    $globals = @($f.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.UserPath -like 'global:*' }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Sort-Object -Unique)

    $usesReadHost = ($text -match '\bRead-Host\b')
    $usesWriteHost = ($text -match '\bWrite-Host\b')
    $isMenu = $name -like 'Menu-*' -or ($text -match '\bswitch\b' -and $usesReadHost)
    $requiresAdmin = ($text -match 'Administrator|Require-Admin|IsInRole')
    $isSensitive = Has-AnyToken $name $licenseTokens -or Has-AnyToken $text $licenseTokens

    $unresolved = @()
    foreach($cn in $calls){
        $l = $cn.ToLowerInvariant()
        if($funcNames.ContainsKey($l)){ continue }
        if($l -match '^(write-host|write-warning|read-host|for|foreach|if|switch|return|break|continue|start-sleep|clear-host|where-object|select-object|sort-object|measure-object|get-date|join-path|test-path|new-item|add-content|set-content|get-content|out-null|get-childitem|get-item|get-command|start-process|pause-script|confirm-action|registrar-log|param)$'){ continue }
        if($l -match '^[a-z]:\\'){ continue }
        # external command unresolved is informational
        if($l -match '^(cmd|powershell|pwsh|net|ping|tracert|nslookup|whois|arp|ipconfig|netstat|route|winget|choco|slmgr|dism|sfc|chkdsk|fsutil|bcdedit|powercfg|schtasks|robocopy|diskpart|reg)$'){ continue }
        $unresolved += $cn
    }
    $unresolved = @($unresolved | Sort-Object -Unique)

    $classification = 'SafeStaticOnly'
    if($isSensitive){ $classification='LicenseActivationSensitive' }
    elseif($dangerHits.Count -gt 0){ $classification='Risky' }
    elseif($usesReadHost){ $classification='Interactive' }
    elseif($mandatory.Count -gt 0){ $classification='NeedsParameters' }
    elseif($requiresAdmin){ $classification='RequiresAdmin' }
    elseif($unresolved.Count -gt 0){ $classification='BrokenCallReference' }
    else {
        if($name -like 'Get-*' -or ($calls.Count -le 3 -and -not $usesWriteHost)){ $classification='SafeSmokeCandidate' }
        else { $classification='ManualReview' }
    }

    $obj = [pscustomobject]@{
        Name = $name
        StartLine = $f.Extent.StartLineNumber
        EndLine = $f.Extent.EndLineNumber
        Parameters = $params
        MandatoryParameters = $mandatory
        Commands = $calls
        Globals = $globals
        UsesReadHost = $usesReadHost
        UsesWriteHost = $usesWriteHost
        DangerousCommands = $dangerHits
        UnresolvedCalls = $unresolved
        IsMenu = $isMenu
        RequiresAdmin = $requiresAdmin
        Classification = $classification
        SmokeStatus = 'NotRun'
        ErrorMessage = $null
        StackTrace = $null
        DurationMs = 0
    }

    if($unresolved.Count -gt 0){
        foreach($u in $unresolved){ [void]$brokenCalls.Add([pscustomobject]@{Function=$name; UnresolvedCall=$u; Line=$f.Extent.StartLineNumber; Reason='No matching local function'}) }
    }
    if($dangerHits.Count -gt 0){ [void]$risky.Add([pscustomobject]@{Function=$name; Reason='Dangerous command usage'; Commands=$dangerHits}) }
    if($isSensitive){ [void]$sensitive.Add([pscustomobject]@{Function=$name; Reason='License/activation sensitive terms detected'}) }

    [void]$allFunctions.Add($obj)
}

if($RunSafeSmokeTests){
    foreach($fn in $allFunctions){
        if($fn.Classification -ne 'SafeSmokeCandidate'){
            switch($fn.Classification){
                'Risky' { $fn.SmokeStatus='SkippedRisky' }
                'Interactive' { $fn.SmokeStatus='SkippedInteractive' }
                'NeedsParameters' { $fn.SmokeStatus='SkippedNeedsParameters' }
                'LicenseActivationSensitive' { $fn.SmokeStatus='SkippedSensitive' }
                default { $fn.SmokeStatus='SkippedManual' }
            }
            continue
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            # isolate by new pwsh process; do not execute risky by classification
            $probe = @"
`$ErrorActionPreference='Stop'
function Pause-Script {}
function Confirm-Action { return `$false }
function Registrar-Log { param(`$m) }
. '$src'
& '$($fn.Name)' | Out-Null
"@
            $tmp = Join-Path $env:TEMP ("syncmaster_probe_" + [guid]::NewGuid().ToString() + ".ps1")
            Set-Content -Path $tmp -Value $probe -Encoding UTF8
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $tmp *> $null
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            $fn.SmokeStatus='Success'
        } catch {
            $fn.SmokeStatus='Failed'
            $fn.ErrorMessage=$_.Exception.Message
            $fn.StackTrace=$_.ScriptStackTrace
        } finally {
            $sw.Stop(); $fn.DurationMs=[int]$sw.ElapsedMilliseconds
        }
    }
}

# Cross with flow-report if exists
$flowPath = Join-Path (Split-Path $OutputRoot -Parent) 'SyncMaster-Flow\flow-report.json'
$menuCross = @()
if(Test-Path $flowPath){
    try {
        $flow = Get-Content $flowPath | ConvertFrom-Json
        foreach($n in $flow){
            $af = $allFunctions | Where-Object { $_.Name -eq $n.Function } | Select-Object -First 1
            $menuCross += [pscustomobject]@{
                Parent = $n.Parent; Key = $n.Key; Title = $n.Title; Function = $n.Function;
                Classification = if($af){$af.Classification}else{'UnknownFunction'};
                SmokeStatus = if($af){$af.SmokeStatus}else{'NotFound'}
            }
        }
    } catch {}
}

if($GenerateReports){
    To-JsonFile $allFunctions (Join-Path $OutputRoot 'function-audit.json')

    $summary = @()
    $summary += '# function-audit'
    $summary += "- source: $src"
    $summary += "- total_functions: $($allFunctions.Count)"
    foreach($g in ($allFunctions | Group-Object Classification | Sort-Object Count -Descending)){
        $summary += "- $($g.Name): $($g.Count)"
    }
    $summary += ''
    $summary += '## top 20 problems'
    $problems = $allFunctions | Where-Object { $_.Classification -in @('BrokenCallReference','Risky','LicenseActivationSensitive','ManualReview') } | Select-Object -First 20
    foreach($p in $problems){ $summary += "- $($p.Name): $($p.Classification)" }
    Set-Content -Path (Join-Path $OutputRoot 'function-audit.md') -Value ($summary -join "`r`n") -Encoding UTF8

    $bf = @('# broken-functions')
    foreach($b in ($allFunctions | Where-Object { $_.Classification -eq 'BrokenCallReference' } | Select-Object -First 500)){
        $bf += "- $($b.Name): unresolved => $([string]::Join(', ', $b.UnresolvedCalls))"
    }
    Set-Content -Path (Join-Path $OutputRoot 'broken-functions.md') -Value ($bf -join "`r`n") -Encoding UTF8

    $rf = @('# risky-functions')
    foreach($r in $risky){ $rf += "- $($r.Function): $([string]::Join(', ', $r.Commands))" }
    Set-Content -Path (Join-Path $OutputRoot 'risky-functions.md') -Value ($rf -join "`r`n") -Encoding UTF8

    $uc = @('# unresolved-calls')
    foreach($u in $brokenCalls){ $uc += "- $($u.Function) -> $($u.UnresolvedCall) (line $($u.Line))" }
    Set-Content -Path (Join-Path $OutputRoot 'unresolved-calls.md') -Value ($uc -join "`r`n") -Encoding UTF8

    $ss = @('# safe-smoke-results')
    foreach($s in ($allFunctions | Sort-Object Name)){
        $msg = if($s.ErrorMessage){ " | error=$($s.ErrorMessage)" } else { '' }
        $ss += "- $($s.Name): $($s.SmokeStatus) ($($s.DurationMs)ms)$msg"
    }
    Set-Content -Path (Join-Path $OutputRoot 'safe-smoke-results.md') -Value ($ss -join "`r`n") -Encoding UTF8

    $mtp = @('# manual-test-plan')
    if($menuCross.Count -gt 0){
        $mtp += '## From flow-report.json'
        foreach($m in $menuCross){ $mtp += "- $($m.Parent) -> $($m.Key) -> $($m.Title) -> $($m.Function) [$($m.Classification)/$($m.SmokeStatus)]" }
    } else {
        $mtp += '- flow-report.json not found; create with New-ScriptFlowTree.ps1 first.'
    }
    Set-Content -Path (Join-Path $OutputRoot 'manual-test-plan.md') -Value ($mtp -join "`r`n") -Encoding UTF8

    if($IncludeCallGraph){
        $cg = @()
        foreach($f in $allFunctions){
            foreach($c in $f.Commands){
                $cg += [pscustomobject]@{ From=$f.Name; To=$c; IsLocal=$funcNames.ContainsKey($c.ToLowerInvariant()) }
            }
        }
        To-JsonFile $cg (Join-Path $OutputRoot 'call-graph.json')
    }
}

# console summary
Write-Host "AUDIT DONE" -ForegroundColor Green
Write-Host "Total functions: $($allFunctions.Count)"
foreach($g in ($allFunctions | Group-Object Classification | Sort-Object Count -Descending)){
    Write-Host ("{0}: {1}" -f $g.Name, $g.Count)
}

exit 0
