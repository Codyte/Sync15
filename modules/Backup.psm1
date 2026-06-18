<#
    Backup.psm1 — backup ZIP e clonagem de disco.
    Extraido do monolito Sync_MasterV14.ps1 (Fase 5). Depende de Core.psm1.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -Force -DisableNameChecking

function Criar-BackupZIP {
    $origemObj = Selecionar-DiretorioDaLista -Titulo "Selecione a pasta para BACKUP (ZIP)"
    if (-not $origemObj) { Write-Host "Operação cancelada."; Pause-Script; return }
    $origem = $origemObj.Caminho
    $destinoZIP = Join-Path -Path $PSScriptRoot -ChildPath ("Backup_" + (Split-Path $origem -Leaf) + "_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".zip")
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($origem, $destinoZIP)
        Write-Host "Backup ZIP criado com sucesso: $destinoZIP" -ForegroundColor Green
        Registrar-Log "Backup ZIP de $origem para $destinoZIP"
    } catch {
        Write-Warning "Erro ao criar o backup ZIP: $($_.Exception.Message)"
    }
    Pause-Script
}

function Restaurar-BackupZIP {
    $zip = Get-ChildItem -Path $PSScriptRoot -Filter *.zip | Out-GridView -Title "Escolha o arquivo ZIP para restaurar" -PassThru
    if (-not $zip) { Write-Host "Operação cancelada."; Pause-Script; return }
    $destinoObj = Selecionar-DiretorioDaLista -Titulo "Selecione o DESTINO para RESTAURAR backup ZIP"
    if (-not $destinoObj) { Write-Host "Operação cancelada."; Pause-Script; return }
    $destino = $destinoObj.Caminho
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip.FullName, $destino)
        Write-Host "Backup ZIP restaurado com sucesso para: $destino" -ForegroundColor Green
        Registrar-Log "Restaurado ZIP $($zip.FullName) para $destino"
    } catch {
        Write-Warning "Erro ao restaurar ZIP: $($_.Exception.Message)"
    }
    Pause-Script
}

function Clonar-Disco {
    $origem = Read-Host "Letra do disco ORIGEM (ex: E:)"
    $destino = Read-Host "Letra do disco DESTINO (ex: F:)"
    if ($origem -eq $destino) { Write-Warning "Origem e destino não podem ser iguais!"; Pause-Script; return }
    $confirm = Confirm-Action "AVISO: Todos os dados do disco DESTINO ($destino) serão APAGADOS! Continuar?"
    if ($confirm) {
        Write-Host "Iniciando clonagem (esta operação pode demorar e não mostra barra de progresso)..." -ForegroundColor Yellow
        $bs = "1MB"
        $cmd = "dd if=\\.\$origem of=\\.\$destino bs=$bs"
        try {
            Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -WindowStyle Hidden -Command $cmd" -Verb RunAs -Wait
            Write-Host "Clonagem finalizada!" -ForegroundColor Green
            Registrar-Log "Clonagem de $origem para $destino"
        } catch {
            Write-Warning "Erro ao clonar disco: $($_.Exception.Message)"
        }
    }
    Pause-Script
}

Export-ModuleMember -Function Criar-BackupZIP, Restaurar-BackupZIP, Clonar-Disco
