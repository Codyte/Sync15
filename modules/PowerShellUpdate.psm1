<#
    PowerShellUpdate.psm1 — atualizacao do PowerShell.
    Extraido do monolito Sync_MasterV14.ps1 (Fase 5). Depende de Core.psm1.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -DisableNameChecking  # SEM -Force: -Force aninhado remove o Core global do launcher (colapsa Registrar-Log/Test-IsAdmin)

function Get-LatestPowerShellVersion {
    [CmdletBinding()]
    param (
        [switch]$Preview
    )
    try {
        if ($Preview) {
            Write-Host "Buscando a versão PREVIEW mais recente no GitHub..." -ForegroundColor Yellow
            $apiUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases"
            $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
            $latestTag = ($response | Where-Object { $_.prerelease -eq $true } | Select-Object -First 1).tag_name
        }
        else {
            Write-Host "Buscando a versão ESTÁVEL mais recente no GitHub..." -ForegroundColor Yellow
            $apiUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
            $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
            $latestTag = $response.tag_name
        }
        if ($latestTag) {
            $version = $latestTag.TrimStart('v')
            Write-Host "Versão mais recente encontrada: $version" -ForegroundColor Green
            return $version
        }
    }
    catch {
        Write-Warning "Não foi possível obter a versão mais recente do GitHub. Verifique sua conexão com a internet."
        return $null
    }
}

function Invoke-WingetInstall {
    <#
      .SYNOPSIS  Instala/atualiza um pacote via winget tratando ausencia E codigo de saida.
      .DESCRIPTION  winget e exe nativo: exit code != 0 NAO lanca excecao, entao um try/catch
        nunca pegaria a falha. Aqui: 1) checa se winget existe (senao $false p/ fallback);
        2) inclui --accept-source-agreements (1o uso prompta o aceite da fonte e travaria o
        menu); 3) decide pelo $LASTEXITCODE. Devolve $true so em sucesso real.
      .OUTPUTS  [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory=$true)][string]$PackageId)

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "winget não encontrado. Tentando download manual..."
        return $false
    }
    Write-Host "Usando winget para instalar/atualizar '$PackageId'..." -ForegroundColor Yellow
    winget install --id $PackageId -e --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
        Write-Host "winget concluído com sucesso." -ForegroundColor Green
        return $true
    }
    Write-Warning ("winget retornou código {0}. Tentando download manual..." -f $LASTEXITCODE)
    return $false
}

function Start-PowerShellInstallation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Version,
        [Parameter(Mandatory=$true)]
        [string]$InstallerUrl,
        [Parameter(Mandatory=$true)]
        [string]$InstallerPath
    )
    Write-Host "Baixando PowerShell versão $Version..." -ForegroundColor Yellow
    Write-Host "URL: $InstallerUrl"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
        Write-Host "Download concluído: $InstallerPath" -ForegroundColor Green

        # Verifica a assinatura Authenticode antes de executar (cadeia valida + assinado pela Microsoft).
        $sig = Get-AuthenticodeSignature -FilePath $InstallerPath
        $signer = $sig.SignerCertificate.Subject
        if ($sig.Status -ne 'Valid' -or $signer -notmatch 'Microsoft') {
            Write-Warning ("Assinatura do instalador NAO confiavel (Status={0}; Signer={1}). ABORTANDO." -f $sig.Status, $signer)
            Remove-Item -LiteralPath $InstallerPath -Force -ErrorAction SilentlyContinue
            return
        }
        Write-Host ("Assinatura válida (Microsoft). Iniciando o instalador..." ) -ForegroundColor Green
        Start-Process msiexec.exe -ArgumentList "/i `"$InstallerPath`"" -Wait
        Write-Host "Instalação da versão $Version concluída!" -ForegroundColor Green
    }
    catch {
        Write-Warning "Falha ao baixar ou instalar o PowerShell $Version."
        Write-Warning "Verifique se a versão existe e se o script tem permissões de administrador."
        Write-Host "Consulte todas as versões disponíveis em: https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Blue
    }
}

function Get-InstallerInfo {
    param($Version)
    try {
        $tagUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/tags/v$Version"
        Invoke-RestMethod -Uri $tagUrl -UseBasicParsing -ErrorAction Stop | Out-Null
    } catch {
        Write-Warning "A versão '$Version' não foi encontrada no repositório do PowerShell."
        return $null
    }
    $osArch = (Get-CimInstance -ClassName Win32_OperatingSystem).OSArchitecture
    $platform = switch -regex ($osArch) {
        "64-bit" { "win-x64" }
        "ARM64"  { "win-arm64" }
        default  { 
            Write-Warning "Arquitetura não reconhecida ($osArch). Assumindo x64."
            "win-x64"
        }
    }
    $downloadUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$Version/PowerShell-$Version-$platform.msi"
    $installerPath = "$env:TEMP\PowerShell-$Version-$platform.msi"
    return @{
        Url = $downloadUrl
        Path = $installerPath
    }
}

function Menu-AtualizacaoPowerShell {
    do {
        Clear-Host
        Write-Host "===============================" -ForegroundColor Cyan
        Write-Host "  MENU DE GESTÃO DO POWERSHELL "
        Write-Host "===============================" -ForegroundColor Cyan
        Write-Host "1. Atualizar para última versão ESTÁVEL"
        Write-Host "2. Instalar última versão PREVIEW (Beta)"
        Write-Host "3. Instalar uma versão ESPECÍFICA"
        Write-Host "4. Exibir versão atual"
        Write-Host "Q. Voltar ao menu principal"
        $opcao = Read-Host "`nEscolha uma opção"

        switch ($opcao) {
            '1' {
                if (-not (Invoke-WingetInstall -PackageId 'Microsoft.PowerShell')) {
                    $version = Get-LatestPowerShellVersion
                    if ($version) {
                        $installerInfo = Get-InstallerInfo -Version $version
                        if ($installerInfo) {
                           Start-PowerShellInstallation -Version $version -InstallerUrl $installerInfo.Url -InstallerPath $installerInfo.Path
                        }
                    }
                }
                Pause-Script
            }
            '2' {
                if (-not (Invoke-WingetInstall -PackageId 'Microsoft.PowerShell.Preview')) {
                    $version = Get-LatestPowerShellVersion -Preview
                    if ($version) {
                        $installerInfo = Get-InstallerInfo -Version $version
                        if ($installerInfo) {
                           Start-PowerShellInstallation -Version $version -InstallerUrl $installerInfo.Url -InstallerPath $installerInfo.Path
                        }
                    }
                }
                Pause-Script
            }
            '3' {
                $versao = Read-Host "Digite a versão exata desejada (ex: 7.4.3, 7.3.12)"
                if ($versao -match "^\d+\.\d+\.\d+.*$") {
                    $installerInfo = Get-InstallerInfo -Version $versao
                    if ($installerInfo) {
                        Start-PowerShellInstallation -Version $versao -InstallerUrl $installerInfo.Url -InstallerPath $installerInfo.Path
                    }
                } else {
                    Write-Warning "Formato de versão inválido. Use o formato X.Y.Z."
                }
                Pause-Script
            }
            '4' {
                Write-Host "Versão atual do PowerShell: $($PSVersionTable.PSVersion.ToString())" -ForegroundColor Cyan
                Pause-Script
            }
            'Q' { break }
            default {
                Write-Host "Opção inválida, tente novamente." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    } while ($opcao.ToUpper() -ne 'Q')
}

Export-ModuleMember -Function Get-LatestPowerShellVersion, Start-PowerShellInstallation, Get-InstallerInfo, Invoke-WingetInstall, Menu-AtualizacaoPowerShell
