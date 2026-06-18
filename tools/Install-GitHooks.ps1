#Requires -Version 5.1
<#
.SYNOPSIS
    Instala o hook git pre-commit que roda tools/Run-Checks.ps1 (lint + Pester).
.DESCRIPTION
    O hook em si nao e versionado (.git/hooks/ fora do controle), por isso este
    script reinstala-o. Rode uma vez apos clonar: tools\Install-GitHooks.ps1
#>
[CmdletBinding()]
param()

$root    = Split-Path $PSScriptRoot -Parent
$hookDir = Join-Path $root '.git\hooks'
if (-not (Test-Path $hookDir)) { Write-Error "Nao parece um repo git (sem $hookDir). Rode 'git init' primeiro."; exit 1 }

$hookPath = Join-Path $hookDir 'pre-commit'
# Shebang sh (Git for Windows usa sh para hooks) chamando pwsh. LF obrigatorio.
$lines = @(
    '#!/bin/sh'
    'pwsh -NoProfile -ExecutionPolicy Bypass -File "tools/Run-Checks.ps1"'
    'if [ $? -ne 0 ]; then'
    '  echo "pre-commit: gate reprovado (lint/Pester). Use --no-verify para forcar (nao recomendado)."'
    '  exit 1'
    'fi'
)
$content = ($lines -join "`n") + "`n"
[System.IO.File]::WriteAllText($hookPath, $content, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Hook pre-commit instalado em: $hookPath" -ForegroundColor Green
Write-Host "Rodando o gate uma vez para validar..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Run-Checks.ps1')
