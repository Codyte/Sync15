# Pester 5 — Fase B: nucleo puro do dominio Rede (modules\Rede.psm1).
# Rodar:  Invoke-Pester -Path .\tests
# Alvo: ConvertFrom-PortSpec (parser de especificacao de portas, sem UI).

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'modules\Core.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $root 'modules\Rede.psm1') -Force -DisableNameChecking
}

Describe 'ConvertFrom-PortSpec' {
    It 'expande intervalos e solta avulsas: "20-22,80,443"' {
        (ConvertFrom-PortSpec -Spec '20-22,80,443') -join ',' | Should -Be '20,21,22,80,443'
    }
    It 'ordena e deduplica' {
        (ConvertFrom-PortSpec -Spec '443,80,80,22') -join ',' | Should -Be '22,80,443'
    }
    It 'aceita espaco e ponto-e-virgula como separadores' {
        (ConvertFrom-PortSpec -Spec '22 80;443') -join ',' | Should -Be '22,80,443'
    }
    It 'ignora intervalo invertido (25-20)' {
        (ConvertFrom-PortSpec -Spec '25-20').Count | Should -Be 0
    }
    It 'descarta portas fora de [1..65535]' {
        (ConvertFrom-PortSpec -Spec '0,70000,443') -join ',' | Should -Be '443'
    }
    It 'ignora tokens nao-numericos' {
        (ConvertFrom-PortSpec -Spec 'abc,ssh,80') -join ',' | Should -Be '80'
    }
    It 'string vazia -> nenhuma porta' {
        (ConvertFrom-PortSpec -Spec '').Count | Should -Be 0
    }
}
