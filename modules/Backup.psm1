<#
    Backup.psm1 — backup ZIP e clonagem de disco.
    Extraido do monolito Sync_MasterV14.ps1 (Fase 5). Depende de Core.psm1.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -DisableNameChecking  # SEM -Force: -Force aninhado remove o Core global do launcher (colapsa Registrar-Log/Test-IsAdmin)

# ───────────────────────── Nucleo (Fase B) ─────────────────────────
# Logica sem UI (sem Write-Host/Read-Host/Pause/Out-GridView). Get-ZipBackupPath e' pura;
# Invoke-Zip* fazem I/O mas retornam objeto-resultado (Sucesso/Mensagem) e nao prompts.
# Os presenters Criar-/Restaurar-BackupZIP consomem estas funcoes.

function Get-ZipBackupPath {
    <#
      .SYNOPSIS  Monta o caminho do .zip de backup. Funcao PURA (sem I/O).
      .DESCRIPTION  Padrao: Backup_{nome-da-pasta}_{yyyyMMdd_HHmmss}.zip dentro de DestinoDir.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$OrigemPath,
        [Parameter(Mandatory=$true)][string]$DestinoDir,
        [datetime]$Timestamp = (Get-Date)
    )
    $nome = "Backup_{0}_{1}.zip" -f (Split-Path $OrigemPath -Leaf), $Timestamp.ToString('yyyyMMdd_HHmmss')
    return (Join-Path -Path $DestinoDir -ChildPath $nome)
}

function Invoke-ZipBackup {
    <#
      .SYNOPSIS  Compacta OrigemDir em DestinoZip. Sem UI; devolve objeto-resultado.
      .OUTPUTS   PSCustomObject { Sucesso, Caminho, Mensagem }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$OrigemDir,
        [Parameter(Mandatory=$true)][string]$DestinoZip
    )
    try {
        if (-not (Test-Path -LiteralPath $OrigemDir -PathType Container)) { throw "Pasta de origem nao encontrada: $OrigemDir" }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($OrigemDir, $DestinoZip)
        return [pscustomobject]@{ Sucesso = $true;  Caminho = $DestinoZip; Mensagem = "Backup ZIP criado: $DestinoZip" }
    } catch {
        return [pscustomobject]@{ Sucesso = $false; Caminho = $DestinoZip; Mensagem = $_.Exception.Message }
    }
}

function Invoke-ZipRestore {
    <#
      .SYNOPSIS  Extrai ZipPath em DestinoDir. Sem UI; devolve objeto-resultado.
      .DESCRIPTION  -Sobrescrever usa o overload overwrite (so PS7/.NET Core); em PS5 ou sem
        o switch cai no extract padrao (lanca se arquivo ja existe).
      .OUTPUTS   PSCustomObject { Sucesso, Destino, Mensagem }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ZipPath,
        [Parameter(Mandatory=$true)][string]$DestinoDir,
        [switch]$Sobrescrever
    )
    try {
        if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) { throw "Arquivo ZIP nao encontrado: $ZipPath" }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if ($Sobrescrever -and $PSVersionTable.PSVersion.Major -ge 7) {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestinoDir, $true)
        } else {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestinoDir)
        }
        return [pscustomobject]@{ Sucesso = $true;  Destino = $DestinoDir; Mensagem = "Restaurado para: $DestinoDir" }
    } catch {
        return [pscustomobject]@{ Sucesso = $false; Destino = $DestinoDir; Mensagem = $_.Exception.Message }
    }
}

function Criar-BackupZIP {
    $origemObj = Selecionar-DiretorioDaLista -Titulo "Selecione a pasta para BACKUP (ZIP)"
    if (-not $origemObj) { Write-Host "Operação cancelada."; Pause-Script; return }
    $origem = $origemObj.Caminho
    # Backups vao para o data dir do usuario (portavel), nao ao lado do script.
    $destinoZIP = Get-ZipBackupPath -OrigemPath $origem -DestinoDir (Get-SyncMasterDataDir -SubPasta 'Backups')
    $res = Invoke-ZipBackup -OrigemDir $origem -DestinoZip $destinoZIP
    if ($res.Sucesso) {
        Write-Host "Backup ZIP criado com sucesso: $($res.Caminho)" -ForegroundColor Green
        Registrar-Log "Backup ZIP de $origem para $destinoZIP"
    } else {
        Write-Warning "Erro ao criar o backup ZIP: $($res.Mensagem)"
    }
    Pause-Script
}

function Restaurar-BackupZIP {
    # Lista os ZIPs do data dir de backups (mesmo local onde Criar-BackupZIP grava).
    $bkpDir = Get-SyncMasterDataDir -SubPasta 'Backups'
    $zips = @(Get-ChildItem -Path $bkpDir -Filter *.zip -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($zips.Count -eq 0) { Write-Host "Nenhum ZIP encontrado em: $bkpDir."; Pause-Script; return }
    # Out-GridView nao existe em Server Core / hosts sem GUI: cai numa lista numerada.
    $zip = $null
    try {
        $zip = $zips | Out-GridView -Title "Escolha o arquivo ZIP para restaurar" -PassThru
    } catch {
        Write-Verbose "Out-GridView indisponivel: $($_.Exception.Message)"
        Write-Host "--- BACKUPS DISPONÍVEIS ---" -ForegroundColor Cyan
        for ($i = 0; $i -lt $zips.Count; $i++) {
            Write-Host ('{0,3}. {1}  ({2:yyyy-MM-dd HH:mm})' -f ($i+1), $zips[$i].Name, $zips[$i].LastWriteTime)
        }
        $sel = Read-Host "Número do ZIP a restaurar (Enter cancela)"
        if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $zips.Count) { $zip = $zips[[int]$sel - 1] }
    }
    if (-not $zip) { Write-Host "Nenhum ZIP selecionado (procurados em: $bkpDir)."; Pause-Script; return }
    $destinoObj = Selecionar-DiretorioDaLista -Titulo "Selecione o DESTINO para RESTAURAR backup ZIP"
    if (-not $destinoObj) { Write-Host "Operação cancelada."; Pause-Script; return }
    $destino = $destinoObj.Caminho
    # -Sobrescrever preserva o comportamento atual (overwrite no PS7); o nucleo cuida do fallback PS5.
    $res = Invoke-ZipRestore -ZipPath $zip.FullName -DestinoDir $destino -Sobrescrever
    if ($res.Sucesso) {
        Write-Host "Backup ZIP restaurado com sucesso para: $destino" -ForegroundColor Green
        Registrar-Log "Restaurado ZIP $($zip.FullName) para $destino"
    } else {
        Write-Warning "Erro ao restaurar ZIP: $($res.Mensagem)"
    }
    Pause-Script
}

function Clonar-Disco {
    $origem  = (Read-Host "Letra do disco ORIGEM (ex: E:)").Trim()
    $destino = (Read-Host "Letra do disco DESTINO (ex: F:)").Trim()
    # Valida que e' MESMO uma letra de disco ("E" ou "E:"): vai cru num -Command elevado,
    # entao texto livre seria injecao de comando E geraria device path \\.\... invalido.
    if ($origem  -notmatch '^[A-Za-z]:?$') { Write-Warning "Origem inválida: informe uma letra de disco (ex.: E:)."; Pause-Script; return }
    if ($destino -notmatch '^[A-Za-z]:?$') { Write-Warning "Destino inválido: informe uma letra de disco (ex.: F:)."; Pause-Script; return }
    $origem  = $origem.Substring(0,1).ToUpper()  + ':'
    $destino = $destino.Substring(0,1).ToUpper() + ':'
    if ($origem -eq $destino) { Write-Warning "Origem e destino não podem ser iguais!"; Pause-Script; return }
    # 'dd' NAO existe no Windows por padrao — sem isto a clonagem falha com erro criptico.
    if (-not (Get-Command dd -ErrorAction SilentlyContinue)) {
        Write-Warning "Ferramenta 'dd' não encontrada no PATH. Instale o 'dd for Windows' (ex.: chocolatey 'dd', ou GnuWin) e tente novamente."
        Pause-Script
        return
    }
    $confirm = Confirm-Action "AVISO: Todos os dados do disco DESTINO ($destino) serão APAGADOS! Continuar?"
    if ($confirm) {
        Write-Host "Iniciando clonagem (esta operação pode demorar e não mostra barra de progresso)..." -ForegroundColor Yellow
        # bs=1M (sufixo padrao do dd). O 'exit $LASTEXITCODE' no filho propaga o codigo do dd
        # p/ o $proc.ExitCode aqui — sem isto o try/catch so via falha do Start-Process e
        # "Clonagem finalizada!" mentia mesmo com dd falhando (disco errado, I/O, etc.).
        $cmd = "dd if=\\.\$origem of=\\.\$destino bs=1M; exit `$LASTEXITCODE"
        try {
            $proc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"$cmd`"" -Verb RunAs -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Host "Clonagem finalizada!" -ForegroundColor Green
                Registrar-Log "Clonagem de $origem para $destino (rc=0)"
            } else {
                Write-Warning ("dd retornou código {0} — clonagem possivelmente NÃO concluída. Confira as letras de disco e tente novamente." -f $proc.ExitCode)
                Registrar-Log "Clonagem de $origem para $destino FALHOU (rc=$($proc.ExitCode))"
            }
        } catch {
            Write-Warning "Erro ao clonar disco: $($_.Exception.Message)"
        }
    }
    Pause-Script
}

Export-ModuleMember -Function Get-ZipBackupPath, Invoke-ZipBackup, Invoke-ZipRestore, Criar-BackupZIP, Restaurar-BackupZIP, Clonar-Disco
