<#
    Rede.psm1 — diagnostico e otimizacao de rede do Sync Master.
    Extraido do monolito Sync_MasterV14.ps1 (Fase 5). Auto-contido; depende
    apenas de Core.psm1 (Pause-Script, Confirm-Action, Registrar-Log).
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -DisableNameChecking  # SEM -Force: -Force aninhado remove o Core global do launcher (colapsa Registrar-Log/Test-IsAdmin)
function Menu-DiagnosticoRede {
    do {
        Clear-Host
        Write-Host "========== DIAGNÓSTICO DE REDE AVANÇADO ==========" -ForegroundColor Cyan
        Write-Host " 1 - Testar Porta TCP Específica"
        Write-Host " 2 - Ping Sweep (Varredura de IPs Ativos na Sub-rede)"
        Write-Host " 3 - Scan de Faixa de Portas TCP"
        Write-Host " 4 - Scan de Dispositivos na Rede (ARP Scan)"
        Write-Host " 5 - Descobrir Nomes de Host (Hostnames) na Rede"
        Write-Host " 6 - Consulta WHOIS/DNS de um Domínio"
        Write-Host " 7 - Scan de Serviços Comuns em um Host"
        Write-Host " 8 - Ver Conexões de Rede Ativas (Netstat)"
        Write-Host " 9 - Testar Velocidade da Internet (Speedtest-cli)"
        Write-Host " Q - Voltar ao Menu Principal"
        Write-Host "================================================="
        $opc = Read-Host "Escolha uma opção"

        switch ($opc.ToUpper()) {
            '1' { Testar-PortaTCP }
            '2' { Ping-Sweep }
            '3' { Scan-PortasTCP }
            '4' { Scan-ARP }
            '5' { Descobrir-Hostnames }
            '6' { Whois-Lookup }
            '7' { Scan-Servicos }
            '8' { Mostrar-Netstat }
            '9' { Instalar-e-Testar-Speedtest }
            'Q' { return }
            default { Write-Warning "Opção inválida. Tente novamente."; Pause-Script }
        }
    } while ($true)
}

function Test-TcpPort {
    # Teste de porta TCP NAO-bloqueante com timeout (BeginConnect+WaitOne).
    # O .Connect() sincrono trava ~20s em portas filtradas; isto retorna em $TimeoutMs.
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][int]$Port,
        [int]$TimeoutMs = 600
    )
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $tcp.BeginConnect($ComputerName, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $tcp.Connected) {
            $tcp.EndConnect($iar)
            return $true
        }
        return $false
    } catch { return $false }
    finally { $tcp.Close() }
}

function Testar-PortaTCP {
    $hostIP = Read-Host "Digite o host/IP para testar"
    $porta  = Read-Host "Digite a porta TCP para testar"
    if ($porta -notmatch '^\d+$') { Write-Warning "Porta inválida."; Pause-Script; return }
    if (Test-TcpPort -ComputerName $hostIP -Port ([int]$porta)) {
        Write-Host "Porta $porta ABERTA em $hostIP" -ForegroundColor Green
    } else {
        Write-Warning "Porta $porta FECHADA ou inacessível em $hostIP"
    }
    Pause-Script
}

function Ping-Sweep {
    $subnet = Read-Host "Digite o prefixo da sub-rede (ex: 192.168.1)"
    if ($subnet -notmatch "^\d{1,3}\.\d{1,3}\.\d{1,3}$") { Write-Warning "Formato de sub-rede inválido."; Pause-Script; return }
    $ips = 1..254 | ForEach-Object { "$subnet.$_" }
    Write-Host "Varrendo $subnet.1-254 ..." -ForegroundColor Yellow

    # PS7: varredura PARALELA (era serial = minutos); PS5: fallback serial.
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $ativos = $ips | ForEach-Object -ThrottleLimit 64 -Parallel {
            if (Test-Connection -TargetName $_ -Count 1 -Quiet -TimeoutSeconds 1 -ErrorAction SilentlyContinue) { $_ }
        }
    } else {
        $ativos = foreach ($ip in $ips) {
            if (Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue) { $ip }
        }
    }

    $ativos = @($ativos) | Sort-Object { [version]$_ }
    foreach ($ip in $ativos) { Write-Host "$ip está ATIVO" -ForegroundColor Green }
    Write-Host ("Concluído: {0} host(s) ativo(s) de 254." -f $ativos.Count) -ForegroundColor Cyan
    Pause-Script
}

function Scan-PortasTCP {
    $alvo = Read-Host "Digite o host/IP para escanear"
    $portas = Read-Host "Digite a faixa de portas (ex: 20-25,80,443)"
    $listaPortas = [System.Collections.Generic.List[int]]::new()
    foreach ($faixa in $portas -split ",") {
        $faixa = $faixa.Trim()
        if ($faixa -match '^(\d+)-(\d+)$') {
            $start = [int]$Matches[1]; $end = [int]$Matches[2]
            if ($start -le $end) { for ($p = $start; $p -le $end; $p++) { $listaPortas.Add($p) } }
        } elseif ($faixa -match '^\d+$') {
            $listaPortas.Add([int]$faixa)
        }
    }
    if ($listaPortas.Count -eq 0) { Write-Warning "Nenhuma porta válida informada."; Pause-Script; return }

    # Teste direto com timeout (sem Start-Job: antes era serial + overhead de processo
    # por porta + hang de ~20s em portas filtradas).
    $abertas = 0
    foreach ($porta in $listaPortas) {
        if (Test-TcpPort -ComputerName $alvo -Port $porta -TimeoutMs 500) {
            Write-Host "Porta $porta ABERTA em $alvo" -ForegroundColor Green
            $abertas++
        }
    }
    Write-Host ("Scan concluído: {0} porta(s) aberta(s) de {1} testada(s)." -f $abertas, $listaPortas.Count) -ForegroundColor Cyan
    Pause-Script
}

function Scan-ARP {
    arp -a | ForEach-Object {
        if ($_ -match "([0-9\.]+) +([0-9A-Fa-f\-]+)") {
            Write-Host "IP: $($matches[1]) | MAC: $($matches[2])" -ForegroundColor Yellow
        }
    }
    Pause-Script
}

function Descobrir-Hostnames {
    $subnet = Read-Host "Digite o prefixo da sub-rede (ex: 192.168.1)"
    if ($subnet -notmatch "^\d{1,3}\.\d{1,3}\.\d{1,3}$") { Write-Warning "Formato de sub-rede inválido."; Pause-Script; return }
    $ips = 1..254 | ForEach-Object { "$subnet.$_" }
    Write-Host "Resolvendo hostnames em $subnet.1-254 ..." -ForegroundColor Yellow

    # PS7: resolucao DNS reversa PARALELA (era serial = minutos); PS5: fallback serial.
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $resultados = $ips | ForEach-Object -ThrottleLimit 64 -Parallel {
            try {
                $hostname = [System.Net.Dns]::GetHostEntry($_).HostName
                if ($hostname -ne $_) { "$_ -> $hostname" }
            } catch { }
        }
    } else {
        $resultados = foreach ($ip in $ips) {
            try {
                $hostname = [System.Net.Dns]::GetHostEntry($ip).HostName
                if ($hostname -ne $ip) { "$ip -> $hostname" }
            } catch { Write-Verbose $_.Exception.Message }
        }
    }

    $resultados = @($resultados)
    foreach ($linha in $resultados) { Write-Host $linha -ForegroundColor Cyan }
    Write-Host ("Concluído: {0} hostname(s) resolvido(s)." -f $resultados.Count) -ForegroundColor Cyan
    Pause-Script
}

function Whois-Lookup {
    $alvo = Read-Host "Digite o domínio para consulta WHOIS/DNS"
    try {
        Resolve-DnsName -Name $alvo | Format-Table
    } catch {
        Write-Warning "Domínio/IP inválido ou não encontrado."
    }
    Pause-Script
}

function Scan-Servicos {
    $alvo = Read-Host "Digite o host/IP para verificar serviços comuns"
    $servicos = @{ "HTTP"=80; "HTTPS"=443; "FTP"=21; "SMB"=445; "RDP"=3389; "SSH"=22 }
    # Test-TcpPort (BeginConnect+timeout) no lugar de Test-NetConnection: este trava
    # ~segundos por porta filtrada e e' bem mais lento que o socket nao-bloqueante.
    foreach ($svc in $servicos.Keys) {
        if (Test-TcpPort -ComputerName $alvo -Port $servicos[$svc] -TimeoutMs 600) {
             Write-Host "$svc ($($servicos[$svc])) ABERTO em $alvo" -ForegroundColor Green
        }
    }
    Pause-Script
}

function Mostrar-Netstat {
    netstat -ano | more
    Pause-Script
}

function Instalar-e-Testar-Speedtest {
    Write-Host "== Teste de Velocidade de Rede ==" -ForegroundColor Cyan

    function Run-Ookla {
        param([switch]$Json)
        $cmd = Get-Command speedtest -ErrorAction SilentlyContinue
        if (-not $cmd) { return $false }

        # Aceita licença/GPDR na 1ª execução; usa JSON para normalizar saída
        $stArgs = @('--accept-license','--accept-gdpr','-f','json')
        $out = & $cmd.Source $stArgs 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $out) { return $false }

        if ($Json) { $out | Write-Output; return $true }

        try {
            $j = $out | ConvertFrom-Json
            $downMbps = [math]::Round(($j.download.bandwidth * 8) / 1Mb, 2)
            $upMbps   = [math]::Round(($j.upload.bandwidth   * 8) / 1Mb, 2)
            $pingMs   = [math]::Round([double]$j.ping.latency, 2)
            $server   = $j.server.name
            $isp      = $j.isp
            Write-Host ("ISP: {0} | Servidor: {1}" -f $isp, $server)
            Write-Host ("Ping: {0} ms | Down: {1} Mbps | Up: {2} Mbps" -f $pingMs, $downMbps, $upMbps) -ForegroundColor Green
            return $true
        } catch {
            Write-Warning "Falha ao interpretar saída do speedtest (Ookla)."
            return $false
        }
    }

    # 1) Preferir o executável oficial (se já existir em PATH)
    if (Run-Ookla) { Pause-Script; return }

    # 2) Tentar módulos PowerShell (instalar/ importar e detectar comando exportado)
    $modCands = @('Speedtest-cli','SpeedtestCLI','Speedtest','posh-speedtest')
    $cmdCands = @('Get-SpeedTest','Invoke-Speedtest','Start-Speedtest','Test-Speedtest','Measure-Speedtest')

    $modLoaded = $false
    foreach ($m in $modCands) {
        try {
            if (-not (Get-Module -Name $m)) {
                if (-not (Get-Module -ListAvailable -Name $m)) {
                    Write-Host "Instalando módulo $m da PSGallery..." -ForegroundColor Yellow
                    Install-Module -Name $m -Force -Scope CurrentUser -Repository PSGallery -AllowClobber -ErrorAction Stop
                }
                Import-Module $m -Force -ErrorAction Stop
            }
            $modLoaded = $true
            break
        } catch {
            Write-Verbose ("Falha ao carregar {0}: {1}" -f $m, $_.Exception.Message)
        }
    }

    if ($modLoaded) {
        # Descobre o comando exportado e executa
        $cmd = $null
        foreach ($c in $cmdCands) {
            $gc = Get-Command $c -ErrorAction SilentlyContinue
            if ($gc) { $cmd = $gc.Name; break }
        }

        if ($cmd) {
            try {
                if ($cmd -eq 'Get-SpeedTest' -and (Get-Command Get-SpeedTestServer -ErrorAction SilentlyContinue)) {
                    $server = Get-SpeedTestServer -Top 1
                    $res = & $cmd -Server $server 2>$null
                } else {
                    $res = & $cmd 2>$null
                }

                if ($res) {
                    # Tenta normalizar saída em tabela; se for objeto simples, imprime direto
                    try {
                        $res | Format-Table -AutoSize
                    } catch {
                        $res | Write-Output
                    }
                    Pause-Script
                    return
                } else {
                    Write-Warning "Módulo carregado, mas o comando '$cmd' não retornou resultados."
                }
            } catch {
                Write-Warning "Erro ao executar '$cmd': $($_.Exception.Message)"
            }
        } else {
            Write-Warning "Módulo importado, porém nenhum comando conhecido de speedtest foi encontrado."
        }
    } else {
        Write-Host "Nenhum módulo de speedtest pôde ser instalado/carregado." -ForegroundColor Yellow
    }

    # 3) Último recurso: instalar a CLI oficial via winget e executar
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        try {
            Write-Host "Instalando Ookla Speedtest CLI via winget..." -ForegroundColor Yellow
            & $winget install --id Ookla.Speedtest.CLI --source winget --silent --accept-source-agreements --accept-package-agreements
            # Tenta novamente com a CLI
            if (Run-Ookla) { Pause-Script; return }
        } catch {
            Write-Warning "Falha no winget: $($_.Exception.Message)"
        }
    } else {
        Write-Host "winget indisponível neste host." -ForegroundColor Yellow
    }

    Write-Warning "Não foi possível executar o teste de velocidade (nenhum método funcionou)."
    Write-Host "Dicas: execute como administrador, verifique proxy/firewall, e garanta acesso à PSGallery/winget."
    Pause-Script
}

function Menu-Rede {
    do {
        Clear-Host; Write-Host "--- CONFIGURAÇÕES E REPAROS DE REDE ---" -ForegroundColor Cyan
        Write-Host "1. Limpar Cache DNS"
        Write-Host "2. Liberar e Renovar Endereço IP (DHCP)"
        Write-Host "3. Redefinir Catálogo Winsock (pode exigir reinicialização)"
        Write-Host "4. Redefinir Pilha TCP/IP (pode exigir reinicialização)"
        Write-Host "5. Testar Conexão com a Internet (Ping Google)"
        Write-Host "6. Gerenciar Nível de Autoajuste TCP"
        Write-Host "7. Otimizar Largura de Banda Reservada (QoS)" -ForegroundColor Green
        Write-Host "Q. Voltar"
        $opcao = Read-Host "Sua escolha"
        switch ($opcao.ToUpper()) {
            '1' { ipconfig /flushdns; Registrar-Log "Rede: flushdns"; Write-Host "Cache DNS limpo."; Pause-Script }
            '2' { ipconfig /release; ipconfig /renew; Registrar-Log "Rede: release+renew DHCP"; Write-Host "IP renovado."; Pause-Script }
            '3' { netsh winsock reset; Registrar-Log "Rede: WINSOCK RESET (requer reboot)"; Write-Host "Winsock redefinido. Reinicie se necessário."; Pause-Script }
            '4' { netsh int ip reset; Registrar-Log "Rede: TCP/IP STACK RESET (requer reboot)"; Write-Host "Pilha TCP/IP redefinida. Reinicie se necessário."; Pause-Script }
            '5' { ping google.com; Pause-Script }
            '6' { Configurar-TcpAutoTuning }
            '7' { Otimizar-QoS }
            'Q' { return }
            default {Write-Warning "Opção inválida."}
        }
    } while($true)
}

function Configurar-TcpAutoTuning {
    Clear-Host; Write-Host "--- GERENCIAMENTO DO NÍVEL DE AUTOAJUSTE TCP ---" -ForegroundColor Cyan
    Write-Host "Status Atual:" -ForegroundColor Yellow
    netsh int tcp show global | Select-String "Receive Window Auto-Tuning Level"
    Write-Host "-----------------------------------------------------"
    Write-Host "Opções:"
    Write-Host "1. Desabilitar Autoajuste (disabled)"
    Write-Host "2. Habilitar Autoajuste (normal - Padrão Recomendado)"
    Write-Host "3. Definir como Restrito (restricted)"
    Write-Host "Q. Voltar"
    $escolha = Read-Host "Sua escolha"

    $level = $null
    switch ($escolha.ToUpper()) {
        '1' { $level = "disabled" }
        '2' { $level = "normal" }
        '3' { $level = "restricted" }
        'Q' { return }
        default { Write-Warning "Opção inválida."; Pause-Script; return }
    }
    if ($level) {
        if (Confirm-Action "Definir Nível de Autoajuste TCP como '$level'?") {
            try {
                netsh int tcp set global autotuninglevel=$level
                Registrar-Log "Rede: TCP autotuninglevel=$level"
                Write-Host "Nível de Autoajuste TCP definido como '$level'." -ForegroundColor Green
                Write-Host "Pode ser necessário reiniciar para que todas as aplicações reconheçam a mudança." -ForegroundColor Yellow
            } catch {
                Write-Warning "Falha ao definir o nível de autoajuste. $($_.Exception.Message)"
            }
        }
    }
    Pause-Script
}

function Otimizar-QoS {
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"
    $regKey = "NonBestEffortLimit"
    do {
        Clear-Host
        Write-Host "--- OTIMIZAÇÃO DO AGENDADOR DE PACOTES QOS ---" -ForegroundColor Cyan
        try {
            $currentValue = Get-ItemPropertyValue -Path $regPath -Name $regKey -ErrorAction SilentlyContinue
            if ($null -ne $currentValue) {
                if ($currentValue -eq 0) { Write-Host "Status Atual: Otimizado (Limite de banda reservada desativado)." -ForegroundColor Green }
                else { Write-Host "Status Atual: Valor personalizado definido ($currentValue)." -ForegroundColor Yellow }
            } else { Write-Host "Status Atual: Padrão do Windows (reserva até 20% da banda)." -ForegroundColor Yellow }
        } catch { Write-Host "Status Atual: Padrão do Windows (reserva até 20% da banda)." -ForegroundColor Yellow }
        Write-Host "------------------------------------------------------------"
        Write-Host "1. Otimizar Rede (Define NonBestEffortLimit = 0)"
        Write-Host "2. Restaurar Padrão do Windows (Deleta a chave)" -ForegroundColor Red
        Write-Host "Q. Voltar"
        $opcao = Read-Host "Sua escolha"
        switch ($opcao.ToUpper()) {
            '1' {
                if (Confirm-Action -Prompt "Confirma a definição de 'NonBestEffortLimit' como 0?") {
                    try {
                        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
                        Set-ItemProperty -Path $regPath -Name $regKey -Value 0 -Type DWord -Force
                        Registrar-Log "Rede: QoS NonBestEffortLimit=0 (otimizado)"
                        Write-Host "Otimização de QoS aplicada com sucesso!" -ForegroundColor Green
                    } catch { Write-Warning "Falha ao aplicar a otimização. Erro: $($_.Exception.Message)" }
                }
                Pause-Script
            }
            '2' {
                if ($null -ne (Get-Item -Path $regPath -ErrorAction SilentlyContinue).GetValue($regKey, $null)) {
                     if (Confirm-Action -Prompt "Confirma a EXCLUSÃO da chave 'NonBestEffortLimit'?") {
                        try {
                            Remove-ItemProperty -Path $regPath -Name $regKey -Force -ErrorAction Stop
                            Registrar-Log "Rede: QoS NonBestEffortLimit removido (padrao Windows)"
                            Write-Host "Padrão do Windows restaurado." -ForegroundColor Green
                        } catch { Write-Warning "Falha ao remover a chave. Erro: $($_.Exception.Message)" }
                    }
                } else { Write-Host "A otimização já não está aplicada." -ForegroundColor Green }
                Pause-Script
            }
            'Q' { return }
            default { Write-Warning "Opção inválida."; Pause-Script }
        }
    } while ($true)
}

Export-ModuleMember -Function Menu-DiagnosticoRede, Test-TcpPort, Testar-PortaTCP, Ping-Sweep, Scan-PortasTCP, Scan-ARP, Descobrir-Hostnames, Whois-Lookup, Scan-Servicos, Mostrar-Netstat, Instalar-e-Testar-Speedtest, Menu-Rede, Configurar-TcpAutoTuning, Otimizar-QoS
