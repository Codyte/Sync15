#Requires -Version 5.1
<#
.SYNOPSIS
    Gate de qualidade local: PSScriptAnalyzer (falha em Error) + Pester.
.DESCRIPTION
    Chamado pelo hook git pre-commit (tools/Install-GitHooks.ps1). Sai com codigo 1
    se houver erro de lint ou teste reprovado, bloqueando o commit.
.PARAMETER FailOnWarning
    Tambem falha se houver Warnings de lint (gate estrito).
#>
[CmdletBinding()]
param([switch]$FailOnWarning)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fail = $false

Write-Host "== Lint (PSScriptAnalyzer) ==" -ForegroundColor Cyan
if (Get-Module -ListAvailable PSScriptAnalyzer) {
    $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
    $params = @{ Path = $root; Recurse = $true }
    if (Test-Path $settings) { $params.Settings = $settings }
    $results  = Invoke-ScriptAnalyzer @params
    $errors   = @($results | Where-Object Severity -eq 'Error')
    $warnings = @($results | Where-Object Severity -eq 'Warning')
    Write-Host ("  {0} Error(s), {1} Warning(s)" -f $errors.Count, $warnings.Count)
    if ($errors.Count -gt 0) {
        $errors | ForEach-Object { Write-Host ("  [E] {0}:{1} {2}" -f (Split-Path $_.ScriptName -Leaf), $_.Line, $_.RuleName) -ForegroundColor Red }
        $fail = $true
    }
    if ($FailOnWarning -and $warnings.Count -gt 0) { $fail = $true }
} else {
    Write-Warning "PSScriptAnalyzer nao instalado; lint pulado."
}

Write-Host "== Testes (Pester) ==" -ForegroundColor Cyan
$testsDir = Join-Path $root 'tests'
if ((Get-Module -ListAvailable Pester | Where-Object Version -ge '5.0') -and (Test-Path $testsDir)) {
    $c = New-PesterConfiguration
    $c.Run.Path        = $testsDir
    $c.Run.PassThru    = $true
    $c.Output.Verbosity = 'Normal'
    $r = Invoke-Pester -Configuration $c
    if ($r.FailedCount -gt 0) { Write-Host ("  Pester: {0} reprovado(s)" -f $r.FailedCount) -ForegroundColor Red; $fail = $true }
    else { Write-Host ("  Pester: {0} OK" -f $r.PassedCount) -ForegroundColor Green }
} else {
    Write-Warning "Pester 5+ ou pasta tests/ ausente; testes pulados."
}

if ($fail) { Write-Host "`nGATE REPROVADO — commit bloqueado." -ForegroundColor Red; exit 1 }
Write-Host "`nGATE OK." -ForegroundColor Green
exit 0
