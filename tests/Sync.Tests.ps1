# Pester 5 — testes das funcoes PURAS do nucleo de sincronizacao (Fase B).
# Rodar:  Invoke-Pester -Path .\tests
# Alvos: Get-RobocopyArgs e Get-RobocopyStatus (Sync.psm1).

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'modules\Core.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $root 'modules\Sync.psm1') -Force -DisableNameChecking
}

Describe 'Get-RobocopyArgs' {
    It 'Unilateral seguro usa /E /XO /COPY:DAT e NAO /MIR' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log'
        $a | Should -Contain '/E'
        $a | Should -Contain '/XO'
        $a | Should -Contain '/COPY:DAT'
        $a | Should -Not -Contain '/MIR'
        $a | Should -Not -Contain '/COPYALL'
    }
    It 'Unilateral -PreservarTudo troca /COPY:DAT por /COPYALL' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -PreservarTudo
        $a | Should -Contain '/COPYALL'
        $a | Should -Not -Contain '/COPY:DAT'
    }
    It 'Espelho usa /MIR /COPYALL e NAO /E /XO' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Espelho -LogPath 'C:\x.log'
        $a | Should -Contain '/MIR'
        $a | Should -Contain '/COPYALL'
        $a | Should -Not -Contain '/E'
        $a | Should -Not -Contain '/XO'
    }
    It '-Simular adiciona /L (dry-run)' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -Simular
        $a | Should -Contain '/L'
    }
    It 'sem -Simular NAO inclui /L' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log'
        $a | Should -Not -Contain '/L'
    }
    It 'origem/destino sao os 2 primeiros args e o log entra via /LOG+' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\meu.log'
        $a[0] | Should -Be 'C:\o'
        $a[1] | Should -Be 'C:\d'
        ($a -join ' ') | Should -Match '/LOG\+:C:\\meu\.log'
    }
    It 'rejeita Modo invalido (ValidateSet)' {
        { Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo 'Bilateral' -LogPath 'C:\x.log' } | Should -Throw
    }
}

Describe 'Get-RobocopyStatus' {
    It 'exit 0 => SemMudancas' {
        (Get-RobocopyStatus -ExitCode 0).Severidade | Should -Be 'SemMudancas'
    }
    It 'exit 1..7 => Sucesso' {
        (Get-RobocopyStatus -ExitCode 1).Severidade | Should -Be 'Sucesso'
        (Get-RobocopyStatus -ExitCode 7).Severidade | Should -Be 'Sucesso'
    }
    It 'exit >=8 => Erro' {
        (Get-RobocopyStatus -ExitCode 8).Severidade  | Should -Be 'Erro'
        (Get-RobocopyStatus -ExitCode 16).Severidade | Should -Be 'Erro'
    }
    It 'devolve o proprio ExitCode no objeto' {
        (Get-RobocopyStatus -ExitCode 3).ExitCode | Should -Be 3
    }
}
