<#
    Install-SyncMaster.ps1 — instala o Sync Master como MODULO do PowerShell.

    Copia o manifesto (SyncMaster.psd1), o launcher (Sync_Master.ps1) e a pasta
    modules\ para o diretorio de modulos do usuario (ou da maquina). Depois disso:
      - as 90+ funcoes ficam disponiveis por autoload (Get-Command -Module SyncMaster);
      - 'Start-SyncMaster' abre o menu de qualquer pasta, em qualquer sessao.

    O estado gravavel (logs/backups/config) NAO vai junto: mora em %LOCALAPPDATA%\SyncMaster
    (ver Get-SyncMasterDataDir), entao o modulo instalado pode ser somente-leitura.

    Uso:
      .\Install-SyncMaster.ps1                  # instala para o usuario atual
      .\Install-SyncMaster.ps1 -Scope AllUsers  # instala para a maquina (precisa admin)
      .\Install-SyncMaster.ps1 -Uninstall       # remove
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('CurrentUser','AllUsers')]
    [string]$Scope = 'CurrentUser',

    # Override do diretorio-raiz de modulos (testes/instalacao portatil). Default: derivado do Scope.
    [string]$ModulesRoot,

    [switch]$Uninstall,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$nome = 'SyncMaster'

# 1) Resolve o diretorio-raiz de modulos (a menos que o chamador force um caminho).
if (-not $ModulesRoot) {
    if ($Scope -eq 'AllUsers') {
        $ModulesRoot = Join-Path $env:ProgramFiles 'PowerShell\Modules'
        if ($PSEdition -ne 'Core') { $ModulesRoot = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules' }
    } else {
        $docs = [Environment]::GetFolderPath('MyDocuments')
        $sub  = if ($PSEdition -eq 'Core') { 'PowerShell\Modules' } else { 'WindowsPowerShell\Modules' }
        $ModulesRoot = Join-Path $docs $sub
    }
}
$destino = Join-Path $ModulesRoot $nome

# 2) Desinstalar.
if ($Uninstall) {
    if (Test-Path $destino) {
        if ($PSCmdlet.ShouldProcess($destino, 'Remover modulo SyncMaster')) {
            Remove-Item $destino -Recurse -Force
            Write-Host "Removido: $destino" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Nada a remover (nao instalado em $destino)." -ForegroundColor DarkGray
    }
    return
}

# 3) Instalar: copia manifesto + launcher + modules\ (sem tests/tools/.git).
$origem = $PSScriptRoot
$itens  = @('SyncMaster.psd1','Sync_Master.ps1','modules')
foreach ($i in $itens) {
    if (-not (Test-Path (Join-Path $origem $i))) { throw "Item de origem ausente: $i (rode a partir da raiz do repo)" }
}

if ((Test-Path $destino) -and -not $Force) {
    Write-Warning "Ja existe: $destino. Use -Force para sobrescrever."
    return
}
if ($PSCmdlet.ShouldProcess($destino, 'Instalar modulo SyncMaster')) {
    if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
    New-Item -ItemType Directory -Path $destino -Force | Out-Null
    Copy-Item (Join-Path $origem 'SyncMaster.psd1')    $destino
    Copy-Item (Join-Path $origem 'Sync_Master.ps1')    $destino
    Copy-Item (Join-Path $origem 'modules')            $destino -Recurse

    # 4) Valida o manifesto instalado.
    $manifesto = Join-Path $destino 'SyncMaster.psd1'
    $info = Test-ModuleManifest -Path $manifesto

    Write-Host ""
    Write-Host "Instalado: $nome v$($info.Version)" -ForegroundColor Green
    Write-Host "  -> $destino"
    Write-Host ""
    Write-Host "Use agora (nova sessao ou esta):" -ForegroundColor Cyan
    Write-Host "  Start-SyncMaster                 # abre o menu"
    Write-Host "  Get-Command -Module $nome        # lista as funcoes"
    Write-Host "  Import-Module $nome              # (opcional; autoload ja' resolve)"
}
