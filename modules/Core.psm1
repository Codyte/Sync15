<#
    Core.psm1 — utilitarios base do Sync Master, sem dependencias de dominio.
    Primeiro modulo extraido do monolito Sync_MasterV14.ps1 (Fase 5 do refator).

    Estado GRAVAVEL (logs, backups, config) mora num data dir do usuario, NAO ao lado
    do script — assim o Sync Master roda de qualquer local e em qualquer PC Windows,
    inclusive de pastas somente-leitura (Program Files, rede, midia). Ver Get-SyncMasterDataDir.
#>

function Get-SyncMasterDataDir {
    <#
      .SYNOPSIS  Retorna (criando) o diretorio GRAVAVEL de dados do Sync Master.
      .DESCRIPTION  Portabilidade: o estado nao acompanha o script. Base resolvida por:
        1) $env:SYNCMASTER_DATA_DIR (override explicito);
        2) %LOCALAPPDATA%\SyncMaster (padrao por-usuario);
        3) %USERPROFILE%\SyncMaster (fallback se LOCALAPPDATA ausente).
      .PARAMETER SubPasta  Subpasta opcional (ex.: 'Logs', 'Backups'); tambem e' criada.
    #>
    param([string]$SubPasta)
    $base = if ($env:SYNCMASTER_DATA_DIR)   { $env:SYNCMASTER_DATA_DIR }
            elseif ($env:LOCALAPPDATA)      { Join-Path $env:LOCALAPPDATA 'SyncMaster' }
            else                            { Join-Path $env:USERPROFILE  'SyncMaster' }
    $dir = if ($SubPasta) { Join-Path $base $SubPasta } else { $base }
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

$script:LogsDir = Get-SyncMasterDataDir -SubPasta 'Logs'

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

# Transcript de SESSAO: captura TUDO que aparece no console (menus, saidas, erros)
# num arquivo cronologico no data dir (Logs/sessao_*.log). Complementa o log diario
# estruturado (Registrar-Log). Best-effort: nunca derruba o script se falhar.
$script:SessionTranscript = $null
function Start-SyncMasterLog {
    [CmdletBinding()]
    param()
    if ($script:SessionTranscript) { return $script:SessionTranscript }  # ja iniciado
    $path = Join-Path (Get-SyncMasterDataDir -SubPasta 'Logs') ("sessao_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))
    try {
        Start-Transcript -Path $path -Append -ErrorAction Stop | Out-Null
        $script:SessionTranscript = $path
        Registrar-Log "=== Sessao iniciada (transcript: $path) ==="
        return $path
    } catch {
        Write-Verbose "Transcript de sessao nao iniciado: $($_.Exception.Message)"
        return $null
    }
}

# Encerra o transcript de sessao (footer). Idempotente; tolerante a falha.
function Stop-SyncMasterLog {
    [CmdletBinding()]
    param()
    if (-not $script:SessionTranscript) { return }
    Registrar-Log "=== Sessao encerrada ==="
    try { Stop-Transcript -ErrorAction Stop | Out-Null } catch { Write-Verbose $_.Exception.Message }
    $script:SessionTranscript = $null
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

Export-ModuleMember -Function Get-SyncMasterDataDir, Start-SyncMasterLog, Stop-SyncMasterLog, Pause-Script, Confirm-Action, Registrar-Log, Visualizar-Logs, Ensure-Dir, Test-IsAdmin, Require-Admin
