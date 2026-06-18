<#
    Sync.psm1 — engine de sincronizacao (robocopy) + diretorios salvos do Sync Master.
    Extraido do monolito Sync_MasterV14.ps1 (Fase 5). Depende de Core.psm1.
    Estado dos diretorios salvos (diretorios.json) mora no data dir do usuario
    (Get-SyncMasterDataDir) para o script ser portatil; migra o legado da raiz uma vez.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -DisableNameChecking  # SEM -Force: -Force aninhado remove o Core global do launcher (colapsa Registrar-Log/Test-IsAdmin)

$script:diretoriosConfigFile = Join-Path (Get-SyncMasterDataDir) 'diretorios.json'
# Migracao 1x: versoes antigas gravavam diretorios.json na raiz do projeto. Se o novo
# local ainda nao tem o arquivo mas o legado existe, traz os diretorios salvos do usuario.
$legadoConfig = Join-Path (Split-Path $PSScriptRoot -Parent) 'diretorios.json'
if (-not (Test-Path $script:diretoriosConfigFile) -and (Test-Path $legadoConfig)) {
    try { Copy-Item -LiteralPath $legadoConfig -Destination $script:diretoriosConfigFile -Force } catch { Write-Verbose $_.Exception.Message }
}
if (Test-Path $script:diretoriosConfigFile) {
    try {
        $script:diretoriosSalvos = Get-Content $script:diretoriosConfigFile -Raw | ConvertFrom-Json
        if ($null -ne $script:diretoriosSalvos -and $script:diretoriosSalvos -isnot [array]) { $script:diretoriosSalvos = @($script:diretoriosSalvos) }
    } catch {
        Write-Warning "Arquivo de configuracao de diretorios corrompido."
        $script:diretoriosSalvos = @()
    }
} else {
    $script:diretoriosSalvos = @()
}
if ($null -eq $script:diretoriosSalvos) { $script:diretoriosSalvos = @() }
function Salvar-Diretorios {
    try {
        $script:diretoriosSalvos | ConvertTo-Json -Depth 5 | Set-Content -Path $diretoriosConfigFile
        return $true
    } catch {
        Write-Warning "ERRO: Não foi possível salvar o arquivo de configuração. $($_.Exception.Message)"
        return $false
    }
}

function Menu-GerenciamentoDiretorios {
    do {
        Clear-Host
        Write-Host "--- GERENCIAMENTO DE DIRETÓRIOS SALVOS ---" -ForegroundColor Cyan
        
        if ($diretoriosSalvos.Count -eq 0) {
            Write-Host "Nenhum diretório salvo." -ForegroundColor Yellow
        } else {
            for ($i = 0; $i -lt $diretoriosSalvos.Count; $i++) {
                Write-Host ('{0,3}. {1,-25} -> {2}' -f ($i+1), $diretoriosSalvos[$i].Nome, $diretoriosSalvos[$i].Caminho)
            }
        }
        
        Write-Host "---------------------------------------------"
        Write-Host "A - Adicionar novo diretório"
        Write-Host "R - Remover um diretório"
        Write-Host "Q - Voltar ao menu principal"
        
        $opcao = Read-Host "Sua escolha"
        
        switch ($opcao.ToUpper()) {
            'A' {
                $nome = Read-Host "Digite um nome/apelido para este diretório (ex: Servidor Principal)"
                if ([string]::IsNullOrWhiteSpace($nome)) { Write-Warning "O nome não pode ser vazio."; Pause-Script; continue }
                
                $caminho = ObterCaminhoPasta -titulo "Selecione a pasta para '$nome'"
                
                if (-not $caminho) {
                    Write-Host "Seleção de pasta cancelada ou falhou. Retornando ao menu." -ForegroundColor Yellow
                    Pause-Script
                    continue 
                }

                $novoDiretorio = [pscustomobject]@{
                    Nome = $nome
                    Caminho = $caminho
                }
                $script:diretoriosSalvos += $novoDiretorio
                if (Salvar-Diretorios) { Write-Host "Diretório '$nome' salvo com sucesso!" -ForegroundColor Green }
                Pause-Script
            }
            'R' {
                if ($diretoriosSalvos.Count -eq 0) { Write-Warning "Não há diretórios para remover."; Pause-Script; continue }
                $numStr = Read-Host "Digite o NÚMERO do diretório a ser removido"
                if ($numStr -match '^\d+$' -and [int]$numStr -ge 1 -and [int]$numStr -le $diretoriosSalvos.Count) {
                    $index = [int]$numStr - 1
                    $nomeRemovido = $diretoriosSalvos[$index].Nome
                    if (Confirm-Action "Tem certeza que deseja remover '$nomeRemovido'?") {
                        $tempList = [System.Collections.Generic.List[object]]::new($diretoriosSalvos)
                        $tempList.RemoveAt($index)
                        $script:diretoriosSalvos = $tempList.ToArray()
                        if (Salvar-Diretorios) { Write-Host "Diretório '$nomeRemovido' removido com sucesso!" -ForegroundColor Green }
                    }
                } else {
                    Write-Warning "Número inválido."
                }
                Pause-Script
            }
            'Q' { return }
            default { Write-Warning "Opção inválida."; Pause-Script }
        }
    } while ($true)
}

function Selecionar-DiretorioDaLista {
    param([string]$Titulo = "Selecione um diretório")
    
    Clear-Host
    Write-Host "--- $Titulo ---" -ForegroundColor Cyan
    
    if ($diretoriosSalvos.Count -eq 0) {
        Write-Host "Nenhum diretório salvo na biblioteca. Indo para seleção manual." -ForegroundColor Yellow
        Pause-Script
        $caminhoManual = ObterCaminhoPasta -titulo "Seleção Manual para $Titulo"
        if ($caminhoManual) {
            return [pscustomobject]@{ Nome = "Manual"; Caminho = $caminhoManual }
        }
        return $null
    }

    for ($i = 0; $i -lt $diretoriosSalvos.Count; $i++) {
        Write-Host ('{0,3}. {1}' -f ($i+1), $diretoriosSalvos[$i].Nome)
    }
    Write-Host "---------------------------------------------"
    Write-Host "M - Selecionar um caminho diferente (Manual)"
    Write-Host "C - Cancelar"
    
    $escolha = Read-Host "Escolha um diretório da lista ou uma opção"
    
    if ($escolha -match '^\d+$' -and [int]$escolha -ge 1 -and [int]$escolha -le $diretoriosSalvos.Count) {
        $index = [int]$escolha - 1
        return $diretoriosSalvos[$index]
    } elseif ($escolha -match '^[Mm]$') {
        $caminhoManual = ObterCaminhoPasta -titulo "Seleção Manual para $Titulo"
        if ($caminhoManual) {
            return [pscustomobject]@{ Nome = "Manual"; Caminho = $caminhoManual }
        }
    }
    
    return $null # Cancelado
}

function ObterCaminhoPasta {
    param([string]$titulo = "Selecione uma pasta")
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.Description = $titulo
        $folderBrowser.ShowNewFolderButton = $true
        if ($folderBrowser.ShowDialog() -eq "OK") { return $folderBrowser.SelectedPath } 
        else { Write-Warning "Seleção de pasta cancelada."; return $null }
    }
    catch {
        Write-Warning "Não foi possível carregar o seletor de pastas gráfico. Usando entrada manual."
        do {
            $caminho = Read-Host -Prompt "Digite o caminho completo para a pasta de '$titulo' (ou Enter para cancelar)"
            if ([string]::IsNullOrWhiteSpace($caminho)) { return $null }
            if (Test-Path -Path $caminho -PathType Container) { return $caminho }
            Write-Warning "Caminho inválido ou não é um diretório. Tente novamente."
        } while ($true)
    }
}

function Iniciar-Sincronizacao {
<#
.SYNOPSIS
    Menu unificado de sincronizacao (v15): junta os modos antes separados em "1" e "1.1".
.DESCRIPTION
    Seleciona origem/destino e oferece, num so lugar, todos os modos com a engine segura
    (checagem de espaco, log e dry-run): SIMULAR, copiar unilateral segura, copiar unilateral
    COMPLETA (/COPYALL, preserva ACL/owner), ESPELHAR (/MIR, destrutivo) e ESTIMAR espaco.
#>
    Clear-Host
    Write-Host "--- SINCRONIZAÇÃO DE ARQUIVOS ---" -ForegroundColor Cyan

    $origemObj = Selecionar-DiretorioDaLista -Titulo "Selecione a ORIGEM da sincronização"
    if (-not $origemObj) { Write-Host "Operação cancelada."; Pause-Script; return }

    $destinoObj = Selecionar-DiretorioDaLista -Titulo "Selecione o DESTINO da sincronização"
    if (-not $destinoObj) { Write-Host "Operação cancelada."; Pause-Script; return }

    $origem  = $origemObj.Caminho
    $destino = $destinoObj.Caminho

    Clear-Host
    Write-Host "ORIGEM : $origem"  -ForegroundColor Green
    Write-Host "DESTINO: $destino" -ForegroundColor Green
    Write-Host ""
    Write-Host "Escolha a operação:" -ForegroundColor Cyan
    Write-Host "  1) SIMULAR (dry-run) - não copia, só lista o que faria"
    Write-Host "  2) COPIAR unilateral SEGURA (dados/tempo; sem permissões)"
    Write-Host "  3) COPIAR unilateral COMPLETA (/COPYALL: preserva ACL/owner - entre servidores)"
    Write-Host "  4) ESPELHAR (/MIR) - destino vira cópia EXATA da origem (APAGA extras no destino)" -ForegroundColor Red
    Write-Host "  5) ESTIMAR tamanho x espaço (relatório)"
    Write-Host "  C) Cancelar"
    $opt = Read-Host "Sua opção"

    switch ($opt.ToUpper()) {
        '1' {
            Start-RobocopyUnilateralSeguro -Origem $origem -Destino $destino -Simular
            Pause-Script
        }
        '2' {
            if (Confirm-Action -Prompt "Confirma cópia unilateral SEGURA?") {
                Start-RobocopyUnilateralSeguro -Origem $origem -Destino $destino
            }
            Pause-Script
        }
        '3' {
            if (Confirm-Action -Prompt "Confirma cópia unilateral COMPLETA (/COPYALL)?") {
                Start-RobocopyUnilateralSeguro -Origem $origem -Destino $destino -PreservarTudo
            }
            Pause-Script
        }
        '4' {
            Write-Warning "ESPELHO /MIR é DESTRUTIVO: apaga no destino tudo que não existe na origem."
            if (Confirm-Action -Prompt "Deseja SIMULAR primeiro (dry-run)?") {
                Start-RobocopyEspelho -Origem $origem -Destino $destino -Simular
                if (-not (Confirm-Action -Prompt "Revisou a simulação. Executar o espelho DE VERDADE agora?")) {
                    Write-Host "Cancelado."; Pause-Script; return
                }
            }
            if (Confirm-Action -Prompt "CONFIRMAÇÃO FINAL: espelhar (pode APAGAR arquivos no destino)?") {
                Start-RobocopyEspelho -Origem $origem -Destino $destino
            } else { Write-Host "Cancelado." }
            Pause-Script
        }
        '5' {
            $cmp = Comparar-EspacoVsOrigemV2 -Origem $origem -Destino $destino
            "`n--- RELATÓRIO ---"
            "Origem........: {0:N2} GB" -f $cmp.OrigemGB
            "Livre destino.: {0:N2} GB" -f $cmp.LivresDestinoGB
            "Margem........: {0:N2} GB" -f $cmp.MargemGB
            "Pode copiar?..: {0}" -f $( if ($cmp.PodeCopiar) { "SIM" } else { "NÃO" } )
            Pause-Script
        }
        default { Write-Host "Cancelado."; Pause-Script }
    }
}

function Executar-Robocopy {
     param([string]$Origem, [string]$Destino, [string]$ModoSincronizacao)
    Write-Host "------------------------------------------------"
    Write-Host "Origem:  $Origem" -ForegroundColor Green
    Write-Host "Destino: $Destino" -ForegroundColor Green
    Write-Host "Modo:    $ModoSincronizacao" -ForegroundColor Green
    Write-Host "------------------------------------------------"
    if ([string]::IsNullOrEmpty($Origem) -or [string]::IsNullOrEmpty($Destino)) { Write-Error "Pastas de origem ou destino não selecionadas. Encerrando."; Pause-Script; return }
    if ((Convert-Path $Origem) -eq (Convert-Path $Destino)) { Write-Error "As pastas de origem e destino não podem ser iguais."; Pause-Script; return }
    if (-not (VerificarEspacoEmDisco -caminho $Destino)) { Write-Host "Abortando devido a espaço em disco insuficiente ou cancelamento do usuário."; Pause-Script; return }
    if (-not (Confirm-Action -Prompt "Confirma o início da sincronização?")) { Write-Host "Operação cancelada."; Pause-Script; return }
    $logFile = Join-Path -Path (Get-SyncMasterDataDir -SubPasta 'Logs') -ChildPath "sincronizacao_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
    Start-Transcript -Path $logFile -Append
    try {
        if ($ModoSincronizacao -eq "Unilateral") {
            Write-Host "Iniciando cópia unilateral (Origem -> Destino)..."
            robocopy "$Origem" "$Destino" /E /COPYALL /R:3 /W:5 /XJ /MT /V
        } elseif ($ModoSincronizacao -eq "Bilateral") {
            Write-Host "Iniciando sincronização bilateral (espelhamento)..."
            Write-Host "Etapa 1: Sincronizando Origem -> Destino..."
            robocopy "$Origem" "$Destino" /MIR /COPYALL /R:3 /W:5 /XJ /MT /V
            Write-Host "Etapa 2: Sincronizando Destino -> Origem..."
            robocopy "$Destino" "$Origem" /MIR /COPYALL /R:3 /W:5 /XJ /MT /V
        }
        if ($LASTEXITCODE -ge 8) { Write-Error "Processo de cópia encontrou erros graves. Verifique o log." }
        elseif ($LASTEXITCODE -ge 1 -and $LASTEXITCODE -lt 8) { Write-Host "Sincronização concluída com sucesso (arquivos foram copiados)." -ForegroundColor Green }
        else { Write-Host "Sincronização concluída. Nenhum arquivo precisou ser copiado." -ForegroundColor Green }
    }
    catch { Write-Error "Ocorreu um erro inesperado durante a cópia: $($_.Exception.Message)" }
    finally { Write-Host "Log de operação detalhado salvo em: $logFile"; Stop-Transcript; Pause-Script }
}

function VerificarEspacoEmDisco {
    param([string]$caminho)

    try {
        # --- DESTINO EM REDE (UNC) ---
        if ($caminho -like "\\*") {
            # \\servidor\compartilhamento\pasta\...
            $partes = $caminho.TrimEnd('\').Split([System.IO.Path]::DirectorySeparatorChar, [System.StringSplitOptions]::RemoveEmptyEntries)
            if ($partes.Count -lt 2) { throw "Caminho UNC inválido: $caminho" }

            $servidor = $partes[0]
            $compartilhamento = $partes[1]

            # Abre sessão CIM no servidor (requer RPC/WMI liberado e permissão)
            $sess = New-CimSession -ComputerName $servidor -ErrorAction Stop
            try {
                # 1) Descobre o caminho físico do compartilhamento (ex: D:\Shares\Softwares)
                $share = Get-CimInstance -CimSession $sess -ClassName Win32_Share -Filter ("Name='{0}'" -f $compartilhamento) -ErrorAction Stop
                if (-not $share -or [string]::IsNullOrWhiteSpace($share.Path)) {
                    throw "Compartilhamento '$compartilhamento' não encontrado em $servidor."
                }

                # 2) Extrai a letra da unidade (DeviceID em Win32_LogicalDisk é 'D:' e NÃO 'D:\')
                $root = [System.IO.Path]::GetPathRoot($share.Path) # ex: 'D:\'
                $driveId = $root.Substring(0,2)                     # 'D:'

                # 3) Consulta espaço livre do disco onde mora o compartilhamento
                $disk = Get-CimInstance -CimSession $sess -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $driveId) -ErrorAction Stop
                $freeSpace = [int64]$disk.FreeSpace
            }
            finally {
                if ($sess) { Remove-CimSession -CimSession $sess -ErrorAction SilentlyContinue }
            }
        }
        else {
            # --- DESTINO LOCAL ---
            $driveLetter = [System.IO.Path]::GetPathRoot($caminho).TrimEnd('\')
            $driveInfo = Get-PSDrive -Name $driveLetter.Trim(":") -ErrorAction Stop
            $freeSpace = [int64]$driveInfo.Free
        }

        if ($freeSpace -lt 1GB) {
            Write-Warning ("Espaço em disco insuficiente no destino ({0:N2} MB livres)." -f ($freeSpace / 1MB))
            return $false
        }

        Write-Host ("Espaço em disco suficiente no destino ({0:N2} GB livres)." -f ($freeSpace / 1GB)) -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Não foi possível validar o espaço em disco para '$caminho'. Detalhe: $($_.Exception.Message)"
        # Permite seguir mediante confirmação, caso o ambiente bloqueie WMI/Firewall
        return Confirm-Action -Prompt "Prosseguir SEM checar espaço em disco?"
    }
}

function ObterModoSincronizacao {
    param()
    Write-Host "Escolha o modo de sincronização:"
    Write-Host "1 - Sincronização Unilateral (Origem -> Destino)"
    Write-Host "2 - Sincronização Bilateral (Espelhamento Mútuo)"
    do {
        $modo = Read-Host -Prompt "Digite o número correspondente ao modo desejado (ou 'C' para cancelar)"
        switch ($modo) {
            "1" { return "Unilateral" }
            "2" { return "Bilateral" }
            "C" { return $null }
            default { Write-Warning "Opção inválida. Escolha '1', '2' ou 'C' para cancelar." }
        }
    } while ($true)
}

function Resolve-ShareToDiskInfoV2 {
    <#
      .SYNOPSIS  Resolve \\servidor\share para caminho físico e disco/volume.
      .OUTPUTS   PSCustomObject { Server, Share, PhysicalPath, DriveId, VolumeName, FreeSpace }
    #>
    param([Parameter(Mandatory=$true)][string]$UncPath)

    if ($UncPath -notlike "\\*") { throw "Caminho não é UNC: $UncPath" }

    $parts = $UncPath.TrimEnd('\').Split([IO.Path]::DirectorySeparatorChar, [StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -lt 2) { throw "UNC inválido: $UncPath" }
    $server = $parts[0]; $shareName = $parts[1]

    # Sessão CIM via DCOM (evita TrustedHosts/WinRM)
    $sess = New-CimSession -ComputerName $server -SessionOption (New-CimSessionOption -Protocol Dcom) -ErrorAction Stop
    try {
        $share = Get-CimInstance -CimSession $sess -ClassName Win32_Share -Filter ("Name='{0}'" -f $shareName) -ErrorAction Stop
        if (-not $share -or [string]::IsNullOrWhiteSpace($share.Path)) {
            throw "Compartilhamento '$shareName' não encontrado em $server."
        }

        $physical = $share.Path # ex: D:\Dados\Softwares
        $root     = [IO.Path]::GetPathRoot($physical)   # ex: D:\

        # 1) tenta Win32_LogicalDisk (discos com letra)
        $driveId = $null; $free = $null; $volName = $null
        if ($root -and $root.Length -ge 2) {
            $driveId = $root.Substring(0,2)             # D:
            $disk = Get-CimInstance -CimSession $sess -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $driveId) -ErrorAction SilentlyContinue
            if ($disk) { $free = [int64]$disk.FreeSpace }
        }

        # 2) fallback para Win32_Volume (montagens sem letra/pontos de montagem)
        if (-not $free -or $free -le 0) {
            $vols = Get-CimInstance -CimSession $sess -ClassName Win32_Volume -ErrorAction Stop
            # Win32_Volume.Name termina com \ (ex: D:\  OU  C:\Mounts\Dados\)
            $vol = $vols | Where-Object { $physical.StartsWith($_.Name, [StringComparison]::OrdinalIgnoreCase) } |
                   Sort-Object { $_.Name.Length } -Descending | Select-Object -First 1
            if ($vol) {
                $free    = [int64]$vol.FreeSpace
                $volName = $vol.Name
                if (-not $driveId -and $vol.DriveLetter) { $driveId = $vol.DriveLetter }
            }
        }

        [pscustomobject]@{
            Server       = $server
            Share        = $shareName
            PhysicalPath = $physical
            DriveId      = $driveId
            VolumeName   = $volName
            FreeSpace    = $free
        }
    }
    finally {
        if ($sess) { Remove-CimSession -CimSession $sess -ErrorAction SilentlyContinue }
    }
}

function VerificarEspacoEmDiscoV2 {
    <#
      .SYNOPSIS  Verifica espaço livre para caminho local ou UNC (DCOM).
      .PARAMETER caminho  Caminho local (C:\...) ou UNC (\\server\share\...)
      .PARAMETER MinLivresGB  Limite mínimo em GB (default 1 GB)
      .RETURNS   [bool]
    #>
    param(
        [Parameter(Mandatory=$true)][string]$caminho,
        [double]$MinLivresGB = 1.0
    )

    try {
        $free = $null

        if ($caminho -like "\\*") {
            $info = Resolve-ShareToDiskInfoV2 -UncPath $caminho
            $free = [int64]$info.FreeSpace
        } else {
            $root = [IO.Path]::GetPathRoot($caminho).TrimEnd('\')
            $drv  = Get-PSDrive -Name $root.Trim(':') -ErrorAction Stop
            $free = [int64]$drv.Free
        }

        if (-not $free -or $free -le 0) {
            Write-Warning "Não foi possível determinar o espaço livre para '$caminho'."
            return $false
        }

        $gb = [Math]::Round($free/1GB,2)
        if ($gb -lt $MinLivresGB) {
            Write-Warning ("Espaço insuficiente no destino ({0:N2} GB livres; mínimo {1:N2} GB)." -f $gb, $MinLivresGB)
            return $false
        }

        Write-Host ("Espaço disponível no destino: {0:N2} GB." -f $gb) -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Falha ao verificar espaço para '$caminho'. Detalhe: $($_.Exception.Message)"
        return $false
    }
}

function Get-TamanhoPastaBytesV2 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -Path $Path -PathType Container)) { throw "Pasta não encontrada: $Path" }
    ($items = Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue) | Out-Null
    return ($items | Measure-Object -Property Length -Sum).Sum
}

function Comparar-EspacoVsOrigemV2 {
    <#
      .SYNOPSIS  Compara tamanho da origem com espaço livre no destino.
      .RETURNS   PSCustomObject { OrigemGB, LivresDestinoGB, MargemGB, PodeCopiar }
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Origem,
        [Parameter(Mandatory=$true)][string]$Destino,
        [double]$MargemSegurancaGB = 2.0
    )

    $tamBytes = Get-TamanhoPastaBytesV2 -Path $Origem
    # reutiliza VerificarEspacoEmDiscoV2 para obter livres
    $livres = $null
    if ($Destino -like "\\*") {
        $info   = Resolve-ShareToDiskInfoV2 -UncPath $Destino
        $livres = [int64]$info.FreeSpace
    } else {
        $root = [IO.Path]::GetPathRoot($Destino).TrimEnd('\')
        $drv  = Get-PSDrive -Name $root.Trim(':')
        $livres = [int64]$drv.Free
    }

    $origemGB = [Math]::Round($tamBytes/1GB,2)
    $livresGB = [Math]::Round($livres/1GB,2)
    $margemGB = [Math]::Round($livresGB - $origemGB,2)
    $ok = ($margemGB -ge $MargemSegurancaGB)

    [pscustomobject]@{
        OrigemGB        = $origemGB
        LivresDestinoGB = $livresGB
        MargemGB        = $margemGB
        PodeCopiar      = $ok
    }
}

# ───────────────────────── Nucleo PURO (Fase B) ─────────────────────────
# Logica sem UI (sem Write-Host/Read-Host/Pause): parametrizavel e testavel.
# Os presenters Start-Robocopy* abaixo consomem estas funcoes.

function Get-RobocopyArgs {
    <#
      .SYNOPSIS  Monta a lista de argumentos do robocopy para os modos seguros V2.
      .DESCRIPTION  Funcao PURA (sem I/O): mesma ordem/flags que os presenters usavam
        inline, agora num so lugar. 'Unilateral' usa /E /XO + (/COPYALL|/COPY:DAT);
        'Espelho' usa /MIR /COPYALL (destrutivo). -Simular adiciona /L (dry-run).
      .OUTPUTS  string[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Origem,
        [Parameter(Mandatory=$true)][string]$Destino,
        [Parameter(Mandatory=$true)][ValidateSet('Unilateral','Espelho')][string]$Modo,
        [Parameter(Mandatory=$true)][string]$LogPath,
        [switch]$Simular,
        [switch]$PreservarTudo
    )
    $comum = @('/R:1','/W:1','/XJ','/MT:8','/V','/TEE',"/LOG+:$LogPath",'/DCOPY:DAT')
    if ($Modo -eq 'Espelho') {
        $rcArgs = @($Origem, $Destino, '/MIR', '/COPYALL') + $comum
    } else {
        $copyFlag = if ($PreservarTudo) { '/COPYALL' } else { '/COPY:DAT' }
        $rcArgs = @($Origem, $Destino, '/E', '/XO') + $comum + @($copyFlag)
    }
    if ($Simular) { $rcArgs += '/L' }
    return ,$rcArgs
}

function Get-RobocopyStatus {
    <#
      .SYNOPSIS  Classifica o exit code do robocopy (era triplicado nos presenters).
      .DESCRIPTION  Funcao PURA. Robocopy: >=8 erro grave; 1-7 houve copias; 0 nada a fazer.
      .OUTPUTS  PSCustomObject { ExitCode, Severidade('Erro'|'Sucesso'|'SemMudancas'), Mensagem }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][int]$ExitCode)
    if ($ExitCode -ge 8) {
        $sev = 'Erro';        $msg = "Robocopy terminou com erros (código $ExitCode)."
    } elseif ($ExitCode -ge 1) {
        $sev = 'Sucesso';     $msg = "Concluído com sucesso (houve cópias/atualizações)."
    } else {
        $sev = 'SemMudancas'; $msg = "Nada a copiar/alterar (já idêntico)."
    }
    [pscustomobject]@{ ExitCode = $ExitCode; Severidade = $sev; Mensagem = $msg }
}

function Start-RobocopyUnilateralSeguro {
    <#
      .SYNOPSIS  Cópia unilateral (Origem -> Destino) com flags seguras e /dry-run opcional.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Origem,
        [Parameter(Mandatory=$true)][string]$Destino,
        [switch]$Simular,          # adiciona /L (lista sem copiar)
        [switch]$IgnorarEspaco,    # pula checagem de espaço
        [switch]$PreservarTudo,    # /COPYALL (ACL/owner/auditing) em vez de /COPY:DAT
        [double]$MinLivresGB = 1.0
    )

    $copiaDesc = if ($PreservarTudo) { 'COMPLETA (/COPYALL: ACL/owner)' } else { 'segura (/COPY:DAT)' }
    Write-Host "------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Origem : $Origem"
    Write-Host "Destino: $Destino"
    Write-Host "Modo   : Unilateral $copiaDesc$(if($Simular){' - SIMULAÇÃO (/L)'}else{''})"
    Write-Host "------------------------------------------------" -ForegroundColor Cyan

    if (-not $IgnorarEspaco) {
        $ok = VerificarEspacoEmDiscoV2 -caminho $Destino -MinLivresGB $MinLivresGB
        if (-not $ok) {
            Write-Warning "Espaço não validado/suficiente. Use -IgnorarEspaco para prosseguir mesmo assim."
            return
        }
    }

    $log = Join-Path -Path (Get-SyncMasterDataDir -SubPasta 'Logs') -ChildPath ("robocopy_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))

    # Argumentos via nucleo puro (Get-RobocopyArgs): /COPYALL preserva ACL/owner/auditing
    # (precisa admin); /COPY:DAT evita Owner/SACL.
    $rcArgs = Get-RobocopyArgs -Origem $Origem -Destino $Destino -Modo 'Unilateral' -LogPath $log -Simular:$Simular -PreservarTudo:$PreservarTudo

    Write-Host "Iniciando robocopy..." -ForegroundColor Yellow
    & robocopy @rcArgs
    $rc = $LASTEXITCODE
    Registrar-Log ("Robocopy unilateral {0} {1} -> {2} (rc={3}){4}" -f $copiaDesc, $Origem, $Destino, $rc, $(if($Simular){' [SIMULACAO]'}else{''}))

    $st = Get-RobocopyStatus -ExitCode $rc
    if ($st.Severidade -eq 'Erro') { Write-Error ("{0} Veja o log: {1}" -f $st.Mensagem, $log) }
    else                           { Write-Host  ("{0} Log: {1}" -f $st.Mensagem, $log) -ForegroundColor Green }
}

function Simular-RobocopyUnilateral {
    param([string]$Origem,[string]$Destino)
    Start-RobocopyUnilateralSeguro -Origem $Origem -Destino $Destino -Simular
}

function Executar-RobocopyUnilateral {
    param([string]$Origem,[string]$Destino,[switch]$IgnorarEspaco)
    Start-RobocopyUnilateralSeguro -Origem $Origem -Destino $Destino -IgnorarEspaco:$IgnorarEspaco
}

function Start-RobocopyEspelho {
    <#
      .SYNOPSIS  Espelha Origem -> Destino com /MIR (DESTRUTIVO: apaga no destino o que nao existe na origem).
      .DESCRIPTION  Checa espaco (V2), loga e suporta /L (dry-run). Preserva ACL/owner via /COPYALL.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Origem,
        [Parameter(Mandatory=$true)][string]$Destino,
        [switch]$Simular,
        [switch]$IgnorarEspaco,
        [double]$MinLivresGB = 1.0
    )

    Write-Host "------------------------------------------------" -ForegroundColor Red
    Write-Host "Origem : $Origem"
    Write-Host "Destino: $Destino"
    Write-Host "Modo   : ESPELHO /MIR$(if($Simular){' - SIMULAÇÃO (/L)'}else{''})" -ForegroundColor Red
    Write-Host "AVISO: tudo no destino que NAO existe na origem sera APAGADO." -ForegroundColor Red
    Write-Host "------------------------------------------------" -ForegroundColor Red

    if (-not $IgnorarEspaco) {
        $ok = VerificarEspacoEmDiscoV2 -caminho $Destino -MinLivresGB $MinLivresGB
        if (-not $ok) {
            Write-Warning "Espaço não validado/suficiente. Use -IgnorarEspaco para prosseguir mesmo assim."
            return
        }
    }

    $log = Join-Path -Path (Get-SyncMasterDataDir -SubPasta 'Logs') -ChildPath ("robocopy_espelho_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))
    $rcArgs = Get-RobocopyArgs -Origem $Origem -Destino $Destino -Modo 'Espelho' -LogPath $log -Simular:$Simular

    Write-Host "Iniciando robocopy (espelho)..." -ForegroundColor Yellow
    & robocopy @rcArgs
    $rc = $LASTEXITCODE
    Registrar-Log ("Robocopy ESPELHO /MIR {0} -> {1} (rc={2}){3}" -f $Origem, $Destino, $rc, $(if($Simular){' [SIMULACAO]'}else{''}))

    $st = Get-RobocopyStatus -ExitCode $rc
    if ($st.Severidade -eq 'Erro') { Write-Error ("{0} Veja o log: {1}" -f $st.Mensagem, $log) }
    else                           { Write-Host  ("{0} Log: {1}" -f $st.Mensagem, $log) -ForegroundColor Green }
}

function Iniciar-SincronizacaoV2 {
    # Retrocompat (v15): os menus "1" e "1.1" foram unificados em Iniciar-Sincronizacao.
    Iniciar-Sincronizacao
}

function Agendar-TarefaSincronizacao {
    Write-Host "--- AGENDAMENTO DE TAREFA DE SINCRONIZAÇÃO ---" -ForegroundColor Cyan
    $hora = Read-Host "Digite a hora para agendar a sincronização diária (formato HH:mm, ex: 22:00)"
    if ($hora -notmatch "^\d{2}:\d{2}$") { Write-Warning "Formato de hora inválido."; Pause-Script; return }
    
    $origemObj = Selecionar-DiretorioDaLista -Titulo "Selecione a ORIGEM da sincronização agendada"
    if (-not $origemObj) { Write-Host "Operação cancelada."; Pause-Script; return }

    $destinoObj = Selecionar-DiretorioDaLista -Titulo "Selecione o DESTINO da sincronização agendada"
    if (-not $destinoObj) { Write-Host "Operação cancelada."; Pause-Script; return }

    # Caminho do SCRIPT DE ENTRADA (nao deste .psm1): o launcher exporta SYNCMASTER_ENTRY.
    # $MyInvocation.MyCommand.Definition aqui dentro do modulo apontava para Sync.psm1 (bug):
    # a Tarefa Agendada chamava o modulo em vez do Sync_MasterV15.ps1.
    $entryScript = if ($env:SYNCMASTER_ENTRY -and (Test-Path $env:SYNCMASTER_ENTRY)) {
        $env:SYNCMASTER_ENTRY
    } else {
        Join-Path (Split-Path $PSScriptRoot -Parent) 'Sync_MasterV15.ps1'
    }
    if (-not (Test-Path $entryScript)) {
        Write-Warning "Script de entrada nao localizado ($entryScript). Abra o Sync Master pelo Sync_MasterV15.ps1 e tente de novo."
        Pause-Script; return
    }

    $nomeTarefa = "SincronizacaoEngOrtiz_" + (Get-Date -Format "yyyyMMdd")
    $trigger = New-ScheduledTaskTrigger -Daily -At $hora
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$entryScript`" -Acao Sincronizar -Origem `"$($origemObj.Caminho)`" -Destino `"$($destinoObj.Caminho)`""
    
    try {
        Register-ScheduledTask -TaskName $nomeTarefa -Trigger $trigger -Action $action -Principal $principal -Description "Sincronização automática configurada pela Ferramenta de Engenharia." -Force
        Write-Host "Tarefa '$nomeTarefa' agendada com sucesso para executar diariamente às $hora!" -ForegroundColor Green
        Registrar-Log "Tarefa agendada: $nomeTarefa"
    } catch {
        Write-Warning "Falha ao agendar a tarefa. Erro: $($_.Exception.Message)"
    }
    Pause-Script
}

Export-ModuleMember -Function Salvar-Diretorios, Menu-GerenciamentoDiretorios, Selecionar-DiretorioDaLista, ObterCaminhoPasta, Iniciar-Sincronizacao, Executar-Robocopy, VerificarEspacoEmDisco, ObterModoSincronizacao, Resolve-ShareToDiskInfoV2, VerificarEspacoEmDiscoV2, Get-TamanhoPastaBytesV2, Comparar-EspacoVsOrigemV2, Get-RobocopyArgs, Get-RobocopyStatus, Start-RobocopyUnilateralSeguro, Start-RobocopyEspelho, Simular-RobocopyUnilateral, Executar-RobocopyUnilateral, Iniciar-SincronizacaoV2, Agendar-TarefaSincronizacao
