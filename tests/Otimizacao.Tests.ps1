# Pester 5 — testes das funcoes PURAS do Sync Master v15.
# Rodar:  Invoke-Pester -Path .\tests
# Alvos: Parse-Selection (Otimizacao.psm1) e Ensure-Dir (Core.psm1).

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'modules\Core.psm1')       -Force -DisableNameChecking
    Import-Module (Join-Path $root 'modules\Otimizacao.psm1') -Force -DisableNameChecking
}

Describe 'Parse-Selection' {
    It 'expande numeros soltos e intervalos: "1 3 5-7"' {
        (Parse-Selection -Selection '1 3 5-7' -Max 10) -join ',' | Should -Be '1,3,5,6,7'
    }
    It 'aceita virgula e ponto-e-virgula como separadores' {
        (Parse-Selection -Selection '1;2,3 4' -Max 10) -join ',' | Should -Be '1,2,3,4'
    }
    It 'deduplica e ordena' {
        (Parse-Selection -Selection '5 1 5 3 1' -Max 10) -join ',' | Should -Be '1,3,5'
    }
    It 'descarta fora do intervalo [1..Max]' {
        (Parse-Selection -Selection '0 5 11' -Max 10) -join ',' | Should -Be '5'
    }
    It 'ignora intervalo invertido (7-5)' {
        (Parse-Selection -Selection '7-5' -Max 10).Count | Should -Be 0
    }
    It 'ignora tokens nao-numericos' {
        (Parse-Selection -Selection 'abc x-y' -Max 10).Count | Should -Be 0
    }
    It 'combina intervalo + solto: "5-7,10"' {
        (Parse-Selection -Selection '5-7,10' -Max 12) -join ',' | Should -Be '5,6,7,10'
    }
}

Describe 'Get-SyncMasterDataDir' {
    It 'respeita o override $env:SYNCMASTER_DATA_DIR e cria a pasta' {
        $old = $env:SYNCMASTER_DATA_DIR
        try {
            $env:SYNCMASTER_DATA_DIR = Join-Path $TestDrive 'dados'
            $d = Get-SyncMasterDataDir
            $d | Should -Be (Join-Path $TestDrive 'dados')
            Test-Path $d | Should -BeTrue
        } finally { $env:SYNCMASTER_DATA_DIR = $old }
    }
    It 'cria a subpasta pedida (ex.: Logs)' {
        $old = $env:SYNCMASTER_DATA_DIR
        try {
            $env:SYNCMASTER_DATA_DIR = Join-Path $TestDrive 'dados2'
            $sub = Get-SyncMasterDataDir -SubPasta 'Logs'
            $sub | Should -Be (Join-Path (Join-Path $TestDrive 'dados2') 'Logs')
            Test-Path $sub | Should -BeTrue
        } finally { $env:SYNCMASTER_DATA_DIR = $old }
    }
}

Describe 'Ensure-Dir' {
    It 'cria o diretorio (inclusive aninhado)' {
        $p = Join-Path $TestDrive 'a\b\c'
        Ensure-Dir -Path $p
        Test-Path $p | Should -BeTrue
    }
    It 'e idempotente (nao lanca se ja existe)' {
        $p = Join-Path $TestDrive 'x\y'
        Ensure-Dir -Path $p
        { Ensure-Dir -Path $p } | Should -Not -Throw
        Test-Path $p | Should -BeTrue
    }
}
