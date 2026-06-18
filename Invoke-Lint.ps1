<#
.SYNOPSIS
    Roda PSScriptAnalyzer sobre os scripts do projeto com a config do repo.
.DESCRIPTION
    Gate de qualidade. Sai com codigo 1 se houver Error (quebra build/CI);
    Warnings sao listados mas nao falham por padrao. Use -FailOnWarning para CI estrito.
.EXAMPLE
    .\Invoke-Lint.ps1
.EXAMPLE
    .\Invoke-Lint.ps1 -FailOnWarning
#>
[CmdletBinding()]
param(
    [string]$Path = $PSScriptRoot,
    [switch]$FailOnWarning
)

if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    Write-Error "PSScriptAnalyzer nao instalado. Rode: Install-Module PSScriptAnalyzer -Scope CurrentUser"
    exit 2
}

$settings = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'
$results  = Invoke-ScriptAnalyzer -Path $Path -Recurse -Settings $settings

$errors   = @($results | Where-Object Severity -eq 'Error')
$warnings = @($results | Where-Object Severity -eq 'Warning')

if ($results) {
    $results | Sort-Object Severity, ScriptName, Line |
        Format-Table @{L='Sev';E={$_.Severity}}, @{L='Line';E={$_.Line}}, RuleName,
                     @{L='Msg';E={$_.Message}}, @{L='File';E={Split-Path $_.ScriptName -Leaf}} -AutoSize -Wrap
}

Write-Host ("`nResumo: {0} Error(s), {1} Warning(s)" -f $errors.Count, $warnings.Count) -ForegroundColor Cyan

if ($errors.Count -gt 0) { exit 1 }
if ($FailOnWarning -and $warnings.Count -gt 0) { exit 1 }
exit 0
