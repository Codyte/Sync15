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
    It 'inclui /NP sempre (sem progresso por-arquivo)' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log'
        $a | Should -Contain '/NP'
    }
    It 'default usa /MT:16' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log'
        $a | Should -Contain '/MT:16'
    }
    It '-Threads troca o valor do /MT' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -Threads 32
        $a | Should -Contain '/MT:32'
        $a | Should -Not -Contain '/MT:16'
    }
    It '-Rapido troca /V por /NDL /NFL' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -Rapido
        $a | Should -Contain '/NDL'
        $a | Should -Contain '/NFL'
        $a | Should -Not -Contain '/V'
    }
    It 'sem -Rapido mantem /V e nao inclui /NDL' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log'
        $a | Should -Contain '/V'
        $a | Should -Not -Contain '/NDL'
    }
    It '-IoNaoBufferizado adiciona /J' {
        $a = Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -IoNaoBufferizado
        $a | Should -Contain '/J'
    }
    It 'rejeita Threads fora de 1..128 (ValidateRange)' {
        { Get-RobocopyArgs -Origem 'C:\o' -Destino 'C:\d' -Modo Unilateral -LogPath 'C:\x.log' -Threads 0 } | Should -Throw
    }
}

Describe 'Test-ParOrigemDestino' {
    BeforeAll {
        $script:oDir = Join-Path ([IO.Path]::GetTempPath()) ("syncpar_o_" + [guid]::NewGuid().ToString('N'))
        $script:dDir = Join-Path ([IO.Path]::GetTempPath()) ("syncpar_d_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:oDir, $script:dDir -Force | Out-Null
    }
    AfterAll {
        Remove-Item -LiteralPath $script:oDir, $script:dDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    It 'aceita origem existente != destino' {
        Test-ParOrigemDestino -Origem $script:oDir -Destino $script:dDir | Should -BeTrue
    }
    It 'rejeita origem inexistente' {
        Test-ParOrigemDestino -Origem (Join-Path $script:oDir 'nao_existe') -Destino $script:dDir -ErrorAction SilentlyContinue | Should -BeFalse
    }
    It 'rejeita origem == destino (mesmo caminho)' {
        Test-ParOrigemDestino -Origem $script:oDir -Destino $script:oDir -ErrorAction SilentlyContinue | Should -BeFalse
    }
    It 'rejeita origem == destino ignorando barra final/case' {
        Test-ParOrigemDestino -Origem $script:oDir -Destino ($script:oDir.ToUpper() + '\') -ErrorAction SilentlyContinue | Should -BeFalse
    }
    It 'rejeita destino DENTRO da origem (aninhado)' {
        $sub = Join-Path $script:oDir 'Backup'
        Test-ParOrigemDestino -Origem $script:oDir -Destino $sub -ErrorAction SilentlyContinue | Should -BeFalse
    }
    It 'rejeita origem DENTRO do destino (aninhado inverso)' {
        $sub = Join-Path $script:dDir 'Sub'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        Test-ParOrigemDestino -Origem $sub -Destino $script:dDir -ErrorAction SilentlyContinue | Should -BeFalse
    }
    It 'NAO confunde prefixo de nome (Dados vs Dados2)' {
        $a = Join-Path ([IO.Path]::GetTempPath()) ("syncpar_Dados_"  + [guid]::NewGuid().ToString('N'))
        $b = "$a`2"
        New-Item -ItemType Directory -Path $a, $b -Force | Out-Null
        try { Test-ParOrigemDestino -Origem $a -Destino $b | Should -BeTrue }
        finally { Remove-Item -LiteralPath $a, $b -Recurse -Force -ErrorAction SilentlyContinue }
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
