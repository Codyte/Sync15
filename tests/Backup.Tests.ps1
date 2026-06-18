# Pester 5 — testes do nucleo de backup ZIP (Fase B).
# Rodar:  Invoke-Pester -Path .\tests
# Alvos: Get-ZipBackupPath (pura) + Invoke-ZipBackup/Invoke-ZipRestore (round-trip em TestDrive).

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'modules\Core.psm1')   -Force -DisableNameChecking
    Import-Module (Join-Path $root 'modules\Backup.psm1') -Force -DisableNameChecking
}

Describe 'Get-ZipBackupPath' {
    It 'monta Backup_{pasta}_{timestamp}.zip no diretorio destino' {
        $ts = [datetime]'2026-06-18T13:45:07'
        $p  = Get-ZipBackupPath -OrigemPath 'C:\dados\Projetos' -DestinoDir 'D:\bkp' -Timestamp $ts
        $p | Should -Be 'D:\bkp\Backup_Projetos_20260618_134507.zip'
    }
    It 'usa apenas o nome-folha da origem (ignora o caminho)' {
        $ts = [datetime]'2026-01-02T03:04:05'
        $p  = Get-ZipBackupPath -OrigemPath 'C:\a\b\c\Fotos' -DestinoDir 'C:\out' -Timestamp $ts
        Split-Path $p -Leaf | Should -Be 'Backup_Fotos_20260102_030405.zip'
    }
}

Describe 'Invoke-ZipBackup / Invoke-ZipRestore (round-trip)' {
    It 'compacta uma pasta e restaura o conteudo identico' {
        $src = Join-Path $TestDrive 'origem'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        Set-Content -Path (Join-Path $src 'a.txt') -Value 'conteudo-A'
        $zip = Join-Path $TestDrive 'out.zip'

        $bk = Invoke-ZipBackup -OrigemDir $src -DestinoZip $zip
        $bk.Sucesso | Should -BeTrue
        Test-Path $zip | Should -BeTrue

        $dst = Join-Path $TestDrive 'restaurado'
        $rs  = Invoke-ZipRestore -ZipPath $zip -DestinoDir $dst
        $rs.Sucesso | Should -BeTrue
        Get-Content (Join-Path $dst 'a.txt') | Should -Be 'conteudo-A'
    }
    It 'Invoke-ZipBackup falha (sem lancar) se a origem nao existe' {
        $r = Invoke-ZipBackup -OrigemDir (Join-Path $TestDrive 'nao-existe') -DestinoZip (Join-Path $TestDrive 'x.zip')
        $r.Sucesso  | Should -BeFalse
        $r.Mensagem | Should -Match 'nao encontrada'
    }
    It 'Invoke-ZipRestore falha (sem lancar) se o ZIP nao existe' {
        $r = Invoke-ZipRestore -ZipPath (Join-Path $TestDrive 'fantasma.zip') -DestinoDir (Join-Path $TestDrive 'd')
        $r.Sucesso  | Should -BeFalse
        $r.Mensagem | Should -Match 'nao encontrado'
    }
    It '-Sobrescrever re-extrai por cima de arquivos ja existentes (PS7)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        $src = Join-Path $TestDrive 'o2'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        Set-Content -Path (Join-Path $src 'f.txt') -Value 'v1'
        $zip = Join-Path $TestDrive 'o2.zip'
        Invoke-ZipBackup -OrigemDir $src -DestinoZip $zip | Out-Null

        $dst = Join-Path $TestDrive 'd2'
        (Invoke-ZipRestore -ZipPath $zip -DestinoDir $dst).Sucesso | Should -BeTrue
        # segunda extracao por cima: sem -Sobrescrever lancaria; com -Sobrescrever passa
        (Invoke-ZipRestore -ZipPath $zip -DestinoDir $dst -Sobrescrever).Sucesso | Should -BeTrue
    }
}
