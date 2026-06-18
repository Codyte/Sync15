<#
    Ativacao.psm1 — ativacao do Windows.
    Extraido do monolito Sync_MasterV14.ps1 (Fase 5). Depende de Core.psm1.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -Force -DisableNameChecking

function Ativar-Crack {
    $url = 'https://get.activated.win'
    Write-Host "ATENCAO: isto baixa e EXECUTA um script remoto de $url (Microsoft Activation Scripts)." -ForegroundColor Yellow
    Write-Host "Executar codigo remoto sem inspecionar e um risco de seguranca." -ForegroundColor Yellow
    if (-not (Confirm-Action -Prompt "Confirma baixar e executar o ativador de $url ?")) {
        Write-Host "Cancelado." -ForegroundColor DarkGray
        Pause-Script
        return
    }
    try {
        $script = Invoke-RestMethod -Uri $url
        Invoke-Expression $script
    } catch {
        Write-Warning "Falha ao executar o ativador. Verifique sua conexão com a internet ou software de antivírus."
    }
    Pause-Script
}

function Menu-Ativacao {
    do {
        Clear-Host; Write-Host "--- GERENCIAMENTO DE ATIVAÇÃO (FERRAMENTAS OFICIAIS) ---" -ForegroundColor Cyan
        Write-Host "1 - Mostrar Status Detalhado da Ativação"
        Write-Host "2 - Instalar uma Chave de Produto (Product Key)"
        Write-Host "3 - Tentar Ativação Online"
        Write-Host "4 - Tentar Ativação Por Crack"
        Write-Host "Q - Voltar ao Menu Principal"
        $opcao = Read-Host "Sua escolha"
        switch ($opcao.ToUpper()) {
            "1" { Mostrar-StatusAtivacao }
            "2" { Instalar-ChaveProduto }
            "3" { Ativar-Windows }
            "4" { Ativar-Crack }
            "Q" { return }
            default { Write-Warning "Opção inválida." }
        }
    } while ($true)
}

function Mostrar-StatusAtivacao {
    Write-Host "Exibindo informações detalhadas de licenciamento..." -ForegroundColor Yellow
    Start-Process -FilePath "cscript.exe" -ArgumentList "//nologo C:\Windows\System32\slmgr.vbs /dlv" -Wait
    Pause-Script
}

function Instalar-ChaveProduto {
    $productKey = Read-Host -Prompt "Por favor, insira a chave de produto legítima (Product Key)"
    if ([string]::IsNullOrWhiteSpace($productKey)) { Write-Warning "Nenhuma chave inserida. Operação cancelada." }
    else {
        Write-Host "Instalando a chave de produto..." -ForegroundColor Yellow
        Start-Process -FilePath "cscript.exe" -ArgumentList "//nologo C:\Windows\System32\slmgr.vbs /ipk $productKey" -Wait
    }
    Pause-Script
}

function Ativar-Windows {
    Write-Host "Tentando ativar o Windows online..." -ForegroundColor Yellow
    Start-Process -FilePath "cscript.exe" -ArgumentList "//nologo C:\Windows\System32\slmgr.vbs /ato" -Wait
    Pause-Script
}

Export-ModuleMember -Function Menu-Ativacao, Mostrar-StatusAtivacao, Instalar-ChaveProduto, Ativar-Windows, Ativar-Crack
