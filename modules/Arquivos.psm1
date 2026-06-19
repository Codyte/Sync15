<#
    Arquivos.psm1 — operacoes de arquivos (duplicados, integridade, permissoes, lixeira).
    Extraido do monolito Sync_MasterV14.ps1 (Fase 5). Depende de Core.psm1.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -DisableNameChecking  # SEM -Force: -Force aninhado remove o Core global do launcher (colapsa Registrar-Log/Test-IsAdmin)

# Microsoft.VisualBasic NAO e' carregado por padrao. Sem ele, [Microsoft.VisualBasic.FileIO.
# FileSystem] em Remove-ToRecycleBin lanca, o catch devolve $false e o caller cai no fallback
# Remove-Item -Force => EXCLUSAO PERMANENTE silenciosa em vez de mandar pra Lixeira. Carrega 1x.
try { Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop } catch { Write-Verbose "Microsoft.VisualBasic indisponivel: $($_.Exception.Message)" }

function Remove-ToRecycleBin {
    param([Parameter(Mandatory)][string]$Path)
    try {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $Path,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
        return $true
    } catch {
        return $false
    }
}

function Menu-GerenciamentoArquivos {
    do {
        Clear-Host
        Write-Host "--- GERENCIAMENTO DE ARQUIVOS E DISCO ---" -ForegroundColor Cyan
        Write-Host "1. Encontrar e Remover Arquivos Duplicados"
        Write-Host "Q. Voltar"
        $opcao = Read-Host "Sua escolha"
        switch ($opcao.ToUpper()) {
            '1' { Encontrar-ArquivosDuplicados }
            'Q' { return }
            default { Write-Warning "Opção inválida."; if (Get-Command Pause-Script -ErrorAction SilentlyContinue) { Pause-Script } else { Read-Host "Enter para continuar" } }
        }
    } while ($true)
}

function Encontrar-ArquivosDuplicados {
    Clear-Host
    Write-Host "--- LOCALIZADOR DE ARQUIVOS DUPLICADOS ---" -ForegroundColor Cyan

# =================== CONFIGURAÇÕES RÁPIDAS ===================
$escopoDedup     = 'Global'      # 'Global' ou 'PorRaiz'
$exigirMesmoNome = $false        # $true para exigir mesmo nome além do hash
$ignorarCaminhos = @('\CoreModules\Help\*\html_files\*', '\Licenses\*', '\InstData\Resources\*')
$tamanhoMinBytes = 0             # ex.: 256KB -> 262144
$algoritmoHash   = 'SHA256'

# Prompt seguro (usa Confirm-Action se existir; senão, Read-Host)
$usarExclusaoReal = $false
if (Get-Command Confirm-Action -ErrorAction SilentlyContinue) {
    $usarExclusaoReal = Confirm-Action -Prompt "Executar exclusão REAL? (enviar para Lixeira quando possível)"
} else {
    $resp = (Read-Host "Executar exclusão REAL? (S/N)").Trim()
    $usarExclusaoReal = $resp -match '^[sSyY]'
}

$modoSimulacao = -not $usarExclusaoReal
$manterCriterio  = 'MaisAntigo'  # 'MaisAntigo' ou 'MaisRecente'
$excluirPadroes  = @('~$*','*.tmp','*.log','*.bak')
$excluirPastas   = @('C:\Windows','C:\Program Files','C:\Program Files (x86)')

# Mostra o modo escolhido
Write-Host ("Modo: {0}" -f ($(if($modoSimulacao){'SIMULAÇÃO'}else{'EXCLUSÃO REAL'}))) `
  -ForegroundColor ($(if($modoSimulacao){'Yellow'}else{'Red'}))

    # =============================================================

    # Seleção de pastas (usa suas funções existentes)
    $pastasParaVerificar = @()
    while ($true) {
        $pastaObj = Selecionar-DiretorioDaLista -Titulo "Selecione uma pasta para ANALISAR (ou Cancele para iniciar)"
        if ($pastaObj) {
            if ($pastasParaVerificar -notcontains $pastaObj.Caminho) {
                $pastasParaVerificar += $pastaObj.Caminho
                Write-Host "Pasta adicionada: $($pastaObj.Caminho)" -ForegroundColor Green
            } else {
                Write-Warning "Esta pasta já foi adicionada."
            }
        } else {
            if (Confirm-Action -Prompt "Concluiu a adição de pastas e deseja iniciar a verificação?") { break }
        }
    }
    if ($pastasParaVerificar.Count -eq 0) {
        Write-Warning "Nenhuma pasta selecionada."
        if (Get-Command Pause-Script -ErrorAction SilentlyContinue) { Pause-Script } else { Read-Host "Enter para continuar" }
        return
    }

    # Normaliza pastas protegidas e padrões
    $protegidas = $excluirPastas | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
    $ignorarLC  = $ignorarCaminhos | ForEach-Object { $_.ToLower() }

    Write-Host "`nAnalisando... Isso pode demorar." -ForegroundColor Yellow

    try {
        # ---------- Enumeração inicial ----------
        $arquivos = Get-ChildItem -Path $pastasParaVerificar -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $nome = $_.Name
                $full = $_.FullName
                if (($excluirPadroes | Where-Object { $nome -like $_ }).Count) { return $false }
                if (($protegidas | Where-Object { $full -like ("{0}\*" -f $_) }).Count) { return $false }
                if ($ignorarLC.Count) {
                    $pLC = $full.ToLower()
                    if (($ignorarLC | Where-Object { $pLC -like ("*{0}*" -f $_) }).Count) { return $false }
                }
                if ($tamanhoMinBytes -gt 0 -and $_.Length -lt $tamanhoMinBytes) { return $false }
                return $true
            }

        if (-not $arquivos) {
            Write-Host "`nNenhum arquivo elegível encontrado." -ForegroundColor Green
            if (Get-Command Pause-Script -ErrorAction SilentlyContinue) { Pause-Script } else { Read-Host "Enter para continuar" }
            return
        }

        # ==== xxHash64 embedado (com 'unchecked') ====
        $xxLoaded = $false
        try { $null = [XxHash64]; $xxLoaded = $true } catch { Write-Verbose $_.Exception.Message }
        if (-not $xxLoaded) {
            Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.CompilerServices;

public static class XxHash64
{
    const ulong P1=11400714785074694791UL, P2=14029467366897019727UL, P3=1609587929392839161UL, P4=9650029242287828579UL, P5=2870177450012600261UL;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    static ulong Rotl(ulong x, int r) => (x << r) | (x >> (64 - r));

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    static ulong Read64(byte[] b, int i) => BitConverter.ToUInt64(b, i);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    static ulong Round(ulong acc, ulong input)
    {
        unchecked { acc += input * P2; acc = Rotl(acc,31); acc *= P1; return acc; }
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    static ulong Merge(ulong acc, ulong val)
    {
        unchecked { acc ^= Round(0, val); acc = acc * P1 + P4; return acc; }
    }

    public static ulong Compute(Stream s, int bufferSize = 1<<20)
    {
        byte[] buf = new byte[bufferSize];
        int read;
        ulong total = 0;
        ulong v1 = unchecked(P1 + P2);
        ulong v2 = P2;
        ulong v3 = 0;
        ulong v4 = unchecked(0UL - P1);
        ulong h = 0;

        while ((read = s.Read(buf, 0, buf.Length)) > 0)
        {
            total += (uint)read;
            int i = 0;

            if (read >= 32)
            {
                int limit = read - 32;
                ulong a = v1, b = v2, c = v3, d = v4;

                unchecked {
                    while (i <= limit)
                    {
                        a = Round(a, Read64(buf, i));
                        b = Round(b, Read64(buf, i + 8));
                        c = Round(c, Read64(buf, i + 16));
                        d = Round(d, Read64(buf, i + 24));
                        i += 32;
                    }

                    h = Rotl(a,1) + Rotl(b,7) + Rotl(c,12) + Rotl(d,18);
                    h = Merge(h, a); h = Merge(h, b); h = Merge(h, c); h = Merge(h, d);
                }
            }
            else
            {
                h = P5;
            }

            unchecked {
                for (; i + 8 <= read; i += 8)
                {
                    ulong k = Read64(buf, i);
                    h ^= Round(0, k);
                    h = Rotl(h, 27) * P1 + P4;
                }

                if (i + 4 <= read)
                {
                    h ^= (ulong)BitConverter.ToUInt32(buf, i) * P1;
                    h = Rotl(h, 23) * P2 + P3;
                    i += 4;
                }

                for (; i < read; i++)
                {
                    h ^= ((ulong)buf[i]) * P5;
                    h = Rotl(h, 11) * P1;
                }

                v1 = h;
                v2 = v3 = v4 = 0;
            }
        }

        unchecked {
            h = v1 + (ulong)total;
            h ^= h >> 33; h *= P2;
            h ^= h >> 29; h *= P3;
            h ^= h >> 32;
            return h;
        }
    }
}
"@
        }

        # ==== helper: xxHash64 com SequentialScan (uso no fallback PS<7) ====
        function Get-FastXxHash64 {
            param([Parameter(Mandatory)][string]$Path)
            try {
                $fs = [System.IO.FileStream]::new(
                    $Path,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::Read,
                    1MB,
                    [System.IO.FileOptions]::SequentialScan
                )
                try { [XxHash64]::Compute($fs) } finally { $fs.Dispose() }
            } catch { $null }
        }

        # ==== núcleo: dedupe por pré-filtro xxHash64 + confirmação SHA256 ====
        function Get-DuplicatesByHashLocal {
            param(
                [Parameter(Mandatory)][System.IO.FileInfo[]]$Files,
                [string]$HashAlg = 'SHA256',
                [int]$MaxDegree = [Environment]::ProcessorCount
            )
            $dups = @()
            $porTamanho = $Files | Group-Object -Property Length | Where-Object { $_.Count -gt 1 }

            $total = $porTamanho.Count; $i = 0
            $isPS7 = ($PSVersionTable.PSVersion.Major -ge 7)

            foreach ($g in $porTamanho) {
                $i++
                if ($total -gt 0) {
                    Write-Progress -Activity "Pré-filtro (xxHash64) / confirmação $HashAlg" `
                                   -Status "Grupo $i de $total (tamanho: $($g.Name) bytes)" `
                                   -PercentComplete ([math]::Round(100*$i/$total,0))
                }

                if ($isPS7) {
                    # --- CAMINHO PARALELO (sem passar ScriptBlock) ---
                    $pre = $g.Group | ForEach-Object -Parallel {
                        $p = $_.FullName
                        $len = $_.Length
                        $fast = $null
                        try {
                            $fs = [System.IO.FileStream]::new(
                                $p,
                                [System.IO.FileMode]::Open,
                                [System.IO.FileAccess]::Read,
                                [System.IO.FileShare]::Read,
                                1MB,
                                [System.IO.FileOptions]::SequentialScan
                            )
                            try { $fast = [XxHash64]::Compute($fs) } finally { $fs.Dispose() }
                        } catch { $fast = $null }
                        [PSCustomObject]@{ Path = $p; Length = $len; Fast = $fast }
                    } -ThrottleLimit $MaxDegree

                    $cand = $pre | Group-Object Fast | Where-Object { $_.Count -gt 1 -and $_.Name } | ForEach-Object { $_.Group }

                    if ($cand) {
                        # 2) confirmação cripto em paralelo (SHA256)
                        $hashes = $cand | ForEach-Object -Parallel {
                            try {
                                $h  = Get-FileHash -Algorithm $using:HashAlg -LiteralPath $_.Path
                                $fi = Get-Item -LiteralPath $_.Path
                                [PSCustomObject]@{
                                    Path          = $_.Path
                                    Length        = $_.Length
                                    Hash          = $h.Hash
                                    CreationTime  = $fi.CreationTime
                                    LastWriteTime = $fi.LastWriteTime
                                }
                            } catch { $null }
                        } -ThrottleLimit $MaxDegree

                        if ($hashes) { $dups += ($hashes | Group-Object Hash | Where-Object { $_.Count -gt 1 }) }
                    }
                }
                else {
                    # --- FALLBACK SEQUENCIAL (PS < 7) ---
                    $pre = foreach ($f in $g.Group) {
                        [PSCustomObject]@{
                            Path   = $f.FullName
                            Length = $f.Length
                            Fast   = Get-FastXxHash64 -Path $f.FullName
                        }
                    }
                    $cand = $pre | Group-Object Fast | Where-Object { $_.Count -gt 1 -and $_.Name } | ForEach-Object { $_.Group }

                    if ($cand) {
                        $hashes = foreach ($c in $cand) {
                            try {
                                $h  = Get-FileHash -Algorithm $HashAlg -LiteralPath $c.Path
                                $fi = Get-Item -LiteralPath $c.Path
                                [PSCustomObject]@{
                                    Path          = $c.Path
                                    Length        = $c.Length
                                    Hash          = $h.Hash
                                    CreationTime  = $fi.CreationTime
                                    LastWriteTime = $fi.LastWriteTime
                                }
                            } catch { $null }
                        }
                        if ($hashes) { $dups += ($hashes | Group-Object Hash | Where-Object { $_.Count -gt 1 }) }
                    }
                }
            }
            Write-Progress -Activity "Pré-filtro (xxHash64) / confirmação $HashAlg" -Completed
            ,$dups
        }

        # ---------- Escolha de escopo: Global x PorRaiz ----------
        $gruposDuplicados = @()
        if ($escopoDedup -ieq 'PorRaiz') {
            foreach ($root in $pastasParaVerificar) {
                try { $rootPath = (Resolve-Path $root -ErrorAction Stop).Path } catch { $rootPath = $root }
                $filesInRoot = $arquivos | Where-Object { $_.FullName -like ("{0}\*" -f $rootPath) }
                if ($filesInRoot.Count -gt 1) {
                    $dupsRoot = Get-DuplicatesByHashLocal -Files $filesInRoot -HashAlg $algoritmoHash
                    if ($dupsRoot) { $gruposDuplicados += $dupsRoot }
                }
            }
        } else {
            # Global
            $gruposDuplicados = Get-DuplicatesByHashLocal -Files $arquivos -HashAlg $algoritmoHash
        }

        if (-not $gruposDuplicados -or $gruposDuplicados.Count -eq 0) {
            Write-Host "`nNenhum arquivo duplicado encontrado." -ForegroundColor Green
            if (Get-Command Pause-Script -ErrorAction SilentlyContinue) { Pause-Script } else { Read-Host "Enter para continuar" }
            return
        }

        # ---------- (Opcional) exigir mesmo nome dentro do grupo de hash ----------
        if ($exigirMesmoNome) {
            $refiltrados = @()
            foreach ($g in $gruposDuplicados) {
                $sub = $g.Group | Group-Object { [System.IO.Path]::GetFileName($_.Path) } | Where-Object { $_.Count -gt 1 }
                foreach ($s in $sub) { $refiltrados += [pscustomobject]@{ Name = 'HashGroup'; Group = $s.Group } }
            }
            $gruposDuplicados = $refiltrados
        }

        # ---------- Exibição e decisão ----------
        Clear-Host
        Write-Warning "Arquivos duplicados encontrados:`n"

        $arquivosParaExcluir = [System.Collections.Generic.List[string]]::new()
        $espacoLiberado = 0L

        foreach ($grupo in $gruposDuplicados) {
            $files = if ($manterCriterio -eq 'MaisRecente') {
                $grupo.Group | Sort-Object @{Expression='CreationTime';Descending=$true}, Path
            } else {
                $grupo.Group | Sort-Object @{Expression='CreationTime';Descending=$false}, Path
            }

            $original = $files[0]
            Write-Host "------------------------------------------------------------"
            Write-Host ("Mantém: {0}" -f $original.Path) -ForegroundColor Green

            $duplicatas = $files | Select-Object -Skip 1
            foreach ($d in $duplicatas) {
                Write-Host ("   -> Duplicado: {0}" -f $d.Path) -ForegroundColor Red
                $arquivosParaExcluir.Add($d.Path)
                try { $espacoLiberado += (Get-Item -LiteralPath $d.Path -ErrorAction Stop).Length } catch {  Write-Verbose $_.Exception.Message }
            }
        }

        $espacoLiberadoMB = [math]::Round($espacoLiberado / 1MB, 2)
        Write-Host "------------------------------------------------------------"
        Write-Host ("Total de duplicatas: {0} | Espaço potencial: {1} MB" -f $arquivosParaExcluir.Count, $espacoLiberadoMB) -ForegroundColor Yellow

        # Confirmação
        $acaoTexto = if ($modoSimulacao) { 'Listar/apenas simular' } else { 'Excluir' }
        if ($arquivosParaExcluir.Count -gt 0 -and (Confirm-Action -Prompt ("{0} os arquivos duplicados ({1})? (Lixeira) - ModoSimulacao={2}" -f $acaoTexto, $arquivosParaExcluir.Count, $modoSimulacao))) {
            foreach ($arquivo in $arquivosParaExcluir) {
                try {
                    if ($modoSimulacao) {
                        Write-Host ("[SIMULAÇÃO] Excluir: {0}" -f $arquivo)
                    } else {
                        Write-Host ("Enviando para Lixeira: {0}" -f $arquivo)
                        $ok = $false
                        if (Get-Command Remove-ToRecycleBin -ErrorAction SilentlyContinue) { $ok = Remove-ToRecycleBin -Path $arquivo }
                        if (-not $ok) {
                            # Lixeira falhou: o fallback apaga DE VEZ. Avisa em vez de escalar em silencio.
                            Write-Warning ("Nao foi possivel mandar para a Lixeira; exclusao PERMANENTE: {0}" -f $arquivo)
                            Remove-Item -LiteralPath $arquivo -Force -ErrorAction Stop
                        }
                        if (Get-Command Registrar-Log -ErrorAction SilentlyContinue) { Registrar-Log ("Arquivo duplicado removido{0}: {1}" -f $(if($ok){' (Lixeira)'}else{' (PERMANENTE)'}), $arquivo) }
                    }
                } catch {
                    Write-Warning ("Falha ao processar '{0}': {1}" -f $arquivo, $_.Exception.Message)
                }
            }

            if ($modoSimulacao) { Write-Host "`nSimulação concluída. Nada foi apagado." -ForegroundColor Yellow }
            else { Write-Host "`nLimpeza concluída! Itens foram para a Lixeira (ou removidos no fallback)." -ForegroundColor Green }
        }

    } catch {
        Write-Error ("Ocorreu um erro: {0}" -f $_.Exception.Message)
    }

    if (Get-Command Pause-Script -ErrorAction SilentlyContinue) { Pause-Script } else { Read-Host "Enter para continuar" }
}

function Verificar-IntegridadeArquivos {
    $pastaObj = Selecionar-DiretorioDaLista -Titulo "Selecione a pasta para verificar a integridade (gerar hashes)"
    if (-not $pastaObj) { Write-Host "Operação cancelada."; Pause-Script; return }
    
    $pasta = $pastaObj.Caminho
    Write-Host "Calculando hashes SHA256 para todos os arquivos em '$pasta'. Isso pode demorar..." -ForegroundColor Yellow
    
    try {
        # SilentlyContinue: 1 arquivo travado/sem acesso nao aborta o relatorio inteiro.
        $hashes = @(Get-ChildItem $pasta -Recurse -File -ErrorAction SilentlyContinue | Get-FileHash -Algorithm SHA256 -ErrorAction SilentlyContinue)
        if ($hashes.Count -eq 0) {
            Write-Warning "Nenhum arquivo legível encontrado em '$pasta'. Nada a gerar."
            Pause-Script; return
        }
        $arquivoHash = Join-Path (Get-SyncMasterDataDir -SubPasta 'Relatorios') ("Integridade_" + (Split-Path $pasta -Leaf) + "_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".csv")
        $hashes | Export-Csv -Path $arquivoHash -NoTypeInformation -Encoding UTF8
        Write-Host ("Relatório de hashes ({0} arquivos) gerado com sucesso em: {1}" -f $hashes.Count, $arquivoHash) -ForegroundColor Green
        Registrar-Log "Verificação de integridade gerada para '$pasta' ($($hashes.Count) arquivos)."
    } catch {
        Write-Warning "Ocorreu um erro ao gerar os hashes: $($_.Exception.Message)"
    }
    Pause-Script
}

function Permissoes-Pasta {
    $pastaObj = Selecionar-DiretorioDaLista -Titulo "Selecione a pasta para ver/modificar permissões"
    if (-not $pastaObj) { Write-Host "Operação cancelada."; Pause-Script; return }
    
    $pasta = $pastaObj.Caminho
    Write-Host "--- PERMISSÕES ATUAIS PARA: $pasta ---" -ForegroundColor Cyan
    icacls $pasta
    Write-Host "-----------------------------------------"
    
    if (Confirm-Action "Deseja modificar as permissões?") {
        $novoUser = Read-Host "Digite o nome do usuário/grupo para adicionar/modificar a permissão (ex: Todos)"
        $permissao = Read-Host "Digite a permissão (F=Controle Total, M=Modificar, RX=Leitura/Execução)"
        
        if ($permissao.ToUpper() -in 'F', 'M', 'RX') {
            try {
                # icacls e' nativo: erro (usuario inexistente, acesso negado) NAO lanca -> decide por $LASTEXITCODE,
                # senao imprimia "sucesso" mesmo falhando. /T aplica recursivamente.
                icacls $pasta /grant "$($novoUser):($permissao)" /T
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Falha ao aplicar permissão (icacls exit $LASTEXITCODE). Verifique o usuário/grupo e execute como Administrador."
                } else {
                    Write-Host "Permissão aplicada com sucesso!" -ForegroundColor Green
                    Registrar-Log "Permissão '$permissao' aplicada para '$novoUser' em '$pasta'"
                }
            } catch {
                Write-Warning "Falha ao aplicar permissão: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "Tipo de permissão inválido."
        }
    }
    Pause-Script
}

Export-ModuleMember -Function Remove-ToRecycleBin, Menu-GerenciamentoArquivos, Encontrar-ArquivosDuplicados, Verificar-IntegridadeArquivos, Permissoes-Pasta
