<#
    Core.psm1 — utilitarios base do Sync Master, sem dependencias de dominio.
    Primeiro modulo extraido do monolito Sync_MasterV14.ps1 (Fase 5 do refator).

    $LogsDir fica encapsulado aqui (escopo de modulo). Como o modulo vive em
    modules/, a pasta Logs/ continua na raiz do projeto (parent do PSScriptRoot).
#>

$script:LogsDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'Logs'
if (-not (Test-Path $script:LogsDir)) {
    New-Item -ItemType Directory -Path $script:LogsDir -Force | Out-Null
}

# Pausa o script ate o usuario pressionar uma tecla.
function Pause-Script {
    Write-Host "Pressione qualquer tecla para voltar ao menu..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Confirmacao S/N. Retorna $true se o usuario digitar S/s.
function Confirm-Action {
    param ([string]$Prompt = "Tem certeza que deseja continuar?")
    $resposta = Read-Host -Prompt "$Prompt (S/N)"
    return $resposta -match '^[Ss]$'
}

# Acrescenta uma linha ao log diario (Logs/log_AAAA-MM-DD.txt).
function Registrar-Log($msg) {
    $log = Join-Path $script:LogsDir ("log_" + (Get-Date -Format 'yyyy-MM-dd') + ".txt")
    $linha = (Get-Date -Format "HH:mm:ss") + " - $msg"
    Add-Content -Path $log -Value $linha
}

# Abre o log mais recente no Notepad.
function Visualizar-Logs {
    $logFile = Get-ChildItem -Path $script:LogsDir -Filter *.txt |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($logFile) {
        notepad $logFile.FullName
    } else {
        Write-Host "Nenhum log encontrado." -ForegroundColor Yellow
        Pause-Script
    }
}

# Garante que um diretorio exista (idempotente).
function Ensure-Dir {
    param([string]$Path)
    try { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    catch { Write-Verbose $_.Exception.Message }
}

# Retorna $true se a sessao atual e elevada (Administrador).
function Test-IsAdmin {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Aborta (throw) se nao estiver elevado. Helper transversal usado por varios modulos.
function Require-Admin {
    if (-not (Test-IsAdmin)) {
        Write-Warning "Execute como Administrador."
        Pause-Script
        throw "Sem privilégios de administrador."
    }
}

Export-ModuleMember -Function Pause-Script, Confirm-Action, Registrar-Log, Visualizar-Logs, Ensure-Dir, Test-IsAdmin, Require-Admin
