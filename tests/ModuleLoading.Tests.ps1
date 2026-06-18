# Pester 5 — regressao de carga de modulos (portabilidade).
# Rodar:  Invoke-Pester -Path .\tests
# Guarda o bug do '-Force' aninhado: cada modulo de dominio importava Core com -Force,
# o que REMOVIA o Core global do launcher -> Registrar-Log/Test-IsAdmin sumiam do
# escopo top-level e quebravam a Tarefa Agendada e o gate de admin do menu.

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $modulesDir = Join-Path $root 'modules'
    # Mesma sequencia do launcher: Core primeiro, depois os demais.
    Import-Module (Join-Path $modulesDir 'Core.psm1') -Force -DisableNameChecking
    Get-ChildItem -Path $modulesDir -Filter '*.psm1' | Where-Object Name -ne 'Core.psm1' |
        ForEach-Object { Import-Module $_.FullName -Force -DisableNameChecking }
}

Describe 'Carga de modulos (apos sequencia completa do launcher)' {
    It 'Core continua disponivel no escopo top-level: <_>' -ForEach @(
        'Registrar-Log','Test-IsAdmin','Get-SyncMasterDataDir','Pause-Script','Confirm-Action'
    ) {
        Get-Command $_ -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    It 'modulos de dominio expoem suas funcoes: <_>' -ForEach @(
        'Iniciar-Sincronizacao','Criar-BackupZIP','Monitorar-Recursos','Ping-Sweep'
    ) {
        Get-Command $_ -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}
