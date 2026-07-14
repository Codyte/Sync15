# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L24    Get-VersionFromReleaseUrl
#   L36    Get-LatestPowerShellVersion
#   L93    Invoke-WingetInstall
#   L120   Install-PowerShellFromMsi
#   L155   Start-PowerShellInstallation
#   L182   Find-PwshPath
#   L207   Install-PowerShell7
#   L260   Get-InstallerInfo
#   L286   Menu-AtualizacaoPowerShell
# ======================= END NAV INDEX =======================

<#
    PowerShellUpdate.psm1 — atualizacao do PowerShell.
    Extraido do monolito legado (Fase 5). Depende de Core.psm1.
#>
Import-Module (Join-Path $PSScriptRoot 'Core.psm1') -DisableNameChecking  # SEM -Force: -Force aninhado remove o Core global do launcher (colapsa Registrar-Log/Test-IsAdmin)

# Último recurso quando api.github.com E aka.ms estão bloqueados (rede corporativa).
# Não precisa estar sempre atualizada: só destrava o bootstrap; o pwsh instalado se atualiza depois.
$script:PinnedPSVersion = '7.5.2'

function Get-VersionFromReleaseUrl {
    <#
      .SYNOPSIS  Extrai a versão de uma URL de release do PowerShell (função pura, testável).
      .EXAMPLE   Get-VersionFromReleaseUrl 'https://github.com/PowerShell/PowerShell/releases/tag/v7.5.2'  # -> 7.5.2
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory=$true)][string]$Url)
    if ($Url -match '/tag/v(\d+\.\d+\.\d+)') { return $Matches[1] }
    return $null
}

function Get-LatestPowerShellVersion {
    [CmdletBinding()]
    param (
        [switch]$Preview,
        # So o bootstrap (Install-PowerShell7) usa a versao pinada: o check de update do
        # startup NAO deve — offline viraria prompt de "atualize" a cada abertura.
        [switch]$UsePinnedFallback
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
        Write-Warning "api.github.com indisponível (bloqueio/rate-limit?). Tentando aka.ms..."
    }
    if ($Preview) { return $null }  # fallbacks abaixo só conhecem a stable

    # Fallback 1: aka.ms redireciona para a página da release estável — a versão vai na URL final.
    try {
        $resp = Invoke-WebRequest -Uri 'https://aka.ms/powershell-release?tag=stable' -UseBasicParsing -ErrorAction Stop
        # PS5 expõe a URL final em BaseResponse.ResponseUri; PS7 em RequestMessage.RequestUri
        $finalUrl = if ($resp.BaseResponse.PSObject.Properties['ResponseUri']) {
            $resp.BaseResponse.ResponseUri.AbsoluteUri
        } else {
            $resp.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
        }
        $version = Get-VersionFromReleaseUrl -Url $finalUrl
        if ($version) {
            Write-Host "Versão mais recente (via aka.ms): $version" -ForegroundColor Green
            return $version
        }
    }
    catch {
        Write-Warning "aka.ms também indisponível. Verifique sua conexão com a internet."
    }

    # Fallback 2: versão pinada — garante que o bootstrap nunca fica sem resposta.
    if (-not $UsePinnedFallback) { return $null }
    Write-Warning ("Usando versão pinada {0} (pode não ser a mais recente)." -f $script:PinnedPSVersion)
    return $script:PinnedPSVersion
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

function Install-PowerShellFromMsi {
    <#
      .SYNOPSIS  Valida a assinatura de um MSI do PowerShell e executa o msiexec.
      .DESCRIPTION  Compartilhado entre o download online (Start-PowerShellInstallation) e a
        instalação offline (MSI local, ex.: pendrive). Devolve $true só em sucesso real.
      .OUTPUTS  [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "MSI não encontrado: $Path"
        return $false
    }
    # Verifica a assinatura Authenticode antes de executar (cadeia valida + assinado pela Microsoft).
    $sig = Get-AuthenticodeSignature -FilePath $Path
    $signer = $sig.SignerCertificate.Subject
    if ($sig.Status -ne 'Valid' -or $signer -notmatch 'Microsoft') {
        Write-Warning ("Assinatura do instalador NAO confiavel (Status={0}; Signer={1}). ABORTANDO." -f $sig.Status, $signer)
        return $false
    }
    Write-Host "Assinatura válida (Microsoft). Iniciando o instalador..." -ForegroundColor Green
    # -PassThru p/ ler o ExitCode: msiexec nao seta $LASTEXITCODE e sem isto a falha/cancelamento
    # (1602/1603) passava como "concluida". 0 = ok; 3010 = ok mas exige reinicio.
    $proc = Start-Process msiexec.exe -ArgumentList "/i `"$Path`"" -Wait -PassThru
    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
        $reinicio = if ($proc.ExitCode -eq 3010) { ' (reinício pendente para concluir)' } else { '' }
        Write-Host ("Instalação concluída!$reinicio") -ForegroundColor Green
        return $true
    }
    Write-Warning ("Instalador msiexec retornou código {0} — instalação NÃO concluída. Execute como Administrador e tente novamente." -f $proc.ExitCode)
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
        if (-not (Install-PowerShellFromMsi -Path $InstallerPath)) {
            Remove-Item -LiteralPath $InstallerPath -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Falha ao baixar ou instalar o PowerShell $Version."
        Write-Warning "Verifique se a versão existe e se o script tem permissões de administrador."
        Write-Host "Consulte todas as versões disponíveis em: https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Blue
    }
}

function Find-PwshPath {
    <#
      .SYNOPSIS  Localiza o pwsh.exe: PATH primeiro, depois caminhos padrão de instalação.
      .DESCRIPTION  Após instalar na MESMA sessão, o PATH do processo é velho e Get-Command
        falha — por isso os caminhos padrão (MSI em ProgramFiles, zip portátil em LOCALAPPDATA).
      .OUTPUTS  [string] caminho completo, ou $null se não encontrado.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $cmd = Get-Command -Name pwsh -ErrorAction SilentlyContinue
    if ($cmd) {
        if ($cmd.Source) { return $cmd.Source } else { return $cmd.Path }
    }
    # [IO.Path]::Combine e nao Join-Path: Join-Path valida o PSDrive e explode com drive inexistente
    $candidatos = @(
        [IO.Path]::Combine("$env:ProgramFiles", 'PowerShell', '7', 'pwsh.exe'),
        [IO.Path]::Combine("$env:LOCALAPPDATA", 'Microsoft', 'powershell', 'pwsh.exe')
    )
    foreach ($c in $candidatos) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Install-PowerShell7 {
    <#
      .SYNOPSIS  Instala o PowerShell 7 com cadeia de fallbacks — funciona em QUALQUER Windows.
      .DESCRIPTION  Ordem: a) winget (se existir); b) MSI do GitHub com assinatura validada
        (precisa admin); c) script oficial aka.ms/install-powershell.ps1 (funciona sem winget);
        d) sem admin → zip portátil em %LOCALAPPDATA%\Microsoft\powershell (sem elevação).
      .OUTPUTS  [bool] $true se o pwsh.exe está disponível ao final.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # a) winget (já trata winget ausente e exit code)
    if (Invoke-WingetInstall -PackageId 'Microsoft.PowerShell') {
        if (Find-PwshPath) { return $true }
    }

    $isAdmin = Test-IsAdmin

    # b) MSI direto do GitHub (assinatura Authenticode validada). MSI exige admin.
    if ($isAdmin) {
        $version = Get-LatestPowerShellVersion -UsePinnedFallback
        if ($version) {
            $info = Get-InstallerInfo -Version $version
            if ($info) {
                Start-PowerShellInstallation -Version $version -InstallerUrl $info.Url -InstallerPath $info.Path
                if (Find-PwshPath) { return $true }
            }
        }
    }

    # c/d) Script oficial da Microsoft — único caminho que funciona sem winget E sem admin.
    try {
        Write-Host "Tentando o instalador oficial (aka.ms/install-powershell.ps1)..." -ForegroundColor Yellow
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $boot = [IO.Path]::Combine("$env:TEMP", 'install-powershell.ps1')
        Invoke-WebRequest -Uri 'https://aka.ms/install-powershell.ps1' -OutFile $boot -UseBasicParsing
        if ($isAdmin) {
            & $boot -UseMSI -Quiet
        } else {
            # Sem admin: zip portátil no perfil do usuário — roda em qualquer máquina sem elevação
            $dest = [IO.Path]::Combine("$env:LOCALAPPDATA", 'Microsoft', 'powershell')
            Write-Host "Sem privilégios de administrador: instalando versão portátil em $dest" -ForegroundColor Yellow
            & $boot -Destination $dest -AddToPath
        }
    }
    catch {
        Write-Warning ("Instalador oficial falhou: {0}" -f $_.Exception.Message)
    }

    return [bool](Find-PwshPath)
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
        Write-Host "5. Instalar de um MSI local (offline, ex.: pendrive)"
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
            '5' {
                $msi = Read-Host "Caminho completo do MSI (ex: E:\PowerShell-7.5.2-win-x64.msi)"
                if ([string]::IsNullOrWhiteSpace($msi)) {
                    Write-Warning "Nenhum caminho informado."
                } else {
                    # Mesma validação de assinatura do caminho online — MSI de pendrive não é confiável por si só
                    Install-PowerShellFromMsi -Path $msi.Trim('"') | Out-Null
                }
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

Export-ModuleMember -Function Get-LatestPowerShellVersion, Get-VersionFromReleaseUrl, Start-PowerShellInstallation, Install-PowerShellFromMsi, Get-InstallerInfo, Invoke-WingetInstall, Find-PwshPath, Install-PowerShell7, Menu-AtualizacaoPowerShell
