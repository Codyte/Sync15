param(
    [string]$ShortcutName = "Sync Master Flow",
    [string]$ScriptPath = ".\SyncMaster-Flow\Start-SyncMasterFlow.ps1",
    [string]$ShortcutDirectory = "$env:USERPROFILE\Desktop",
    [switch]$RunAsAdmin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([Parameter(Mandatory)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $Path))
}

function Ensure-LauncherFile {
    param([Parameter(Mandatory)][string]$LauncherPath)

    $launcherDir = Split-Path -Parent $LauncherPath
    if (-not (Test-Path -LiteralPath $launcherDir -PathType Container)) {
        New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $LauncherPath -PathType Leaf) { return }

    $content = @'
[CmdletBinding()]
param(
    [switch]$NoRiskyActions = $true,
    [switch]$AllowRiskyActions,
    [switch]$AllowSensitiveActions,
    [string]$StartMenuFunction
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$FlowJson = Join-Path $ScriptRoot 'flow-report.json'
$MenuRoot = Join-Path $ScriptRoot 'menu'

if (-not (Test-Path -LiteralPath $FlowJson -PathType Leaf)) { throw "flow-report.json not found: $FlowJson" }
if (-not (Test-Path -LiteralPath $MenuRoot -PathType Container)) { throw "menu directory not found: $MenuRoot" }

$Flow = Get-Content -Path $FlowJson | ConvertFrom-Json
Get-ChildItem -Path $MenuRoot -Filter 'main.ps1' -Recurse -File | ForEach-Object { . $_.FullName }

function Get-ChildrenByParent {
    param([string]$ParentName)
    @($Flow | Where-Object { $_.Parent -eq $ParentName })
}

function Show-MenuLoop {
    param([string]$ParentName,[string]$Caption)
    while($true){
        $items = Get-ChildrenByParent -ParentName $ParentName
        if($items.Count -eq 0){ return }
        Write-Host ""
        Write-Host "=== $Caption ===" -ForegroundColor Cyan
        foreach($i in $items){ Write-Host ("{0} - {1}" -f $i.Key,$i.Title) }
        $choice = Read-Host 'Escolha uma opção'
        if($choice -match '^[Qq]$'){ return }
        $node = $items | Where-Object { ([string]$_.Key).ToLowerInvariant() -eq $choice.ToLowerInvariant() } | Select-Object -First 1
        if(-not $node){ continue }
        $child = Get-ChildrenByParent -ParentName ([string]$node.Function)
        if($child.Count -gt 0){
            Show-MenuLoop -ParentName ([string]$node.Function) -Caption ([string]$node.Title)
        } else {
            $fn = [string]$node.Function
            if(Get-Command -Name $fn -ErrorAction SilentlyContinue){ & $fn } else { Write-Warning "Function not loaded: $fn" }
        }
    }
}

if($StartMenuFunction){ Show-MenuLoop -ParentName $StartMenuFunction -Caption $StartMenuFunction }
else { Show-MenuLoop -ParentName '__ROOT__' -Caption 'SyncMaster Flow' }
'@

    Set-Content -Path $LauncherPath -Value $content -Encoding UTF8
}

$ScriptFullPath = Resolve-FullPath -Path $ScriptPath
Ensure-LauncherFile -LauncherPath $ScriptFullPath
if (-not (Test-Path -LiteralPath $ScriptFullPath -PathType Leaf)) { throw "Script not found: $ScriptFullPath" }
$WorkingDirectory = Split-Path -Parent $ScriptFullPath

$PwshPath = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
if (-not $PwshPath) { $PwshPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
if (-not (Test-Path -LiteralPath $PwshPath -PathType Leaf)) { throw "PowerShell not found." }

if (-not (Test-Path -LiteralPath $ShortcutDirectory -PathType Container)) { New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null }
$ShortcutPath = Join-Path $ShortcutDirectory "$ShortcutName.lnk"

$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)

if ($RunAsAdmin) {
    $Shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $ep = $PwshPath.Replace("'","''")
    $es = $ScriptFullPath.Replace("'","''")
    $ew = $WorkingDirectory.Replace("'","''")
    $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"Start-Process -FilePath '$ep' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `"$es`"' -WorkingDirectory '$ew' -Verb RunAs`""
} else {
    $Shortcut.TargetPath = $PwshPath
    $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptFullPath`""
}

$Shortcut.WorkingDirectory = $WorkingDirectory
$Shortcut.WindowStyle = 1
$Shortcut.Description = "Executar Sync Master Flow"
$Shortcut.IconLocation = "$PwshPath,0"
$Shortcut.Save()

Write-Host "Atalho criado:" -ForegroundColor Green
Write-Host $ShortcutPath
Write-Host "Launcher garantido em:"
Write-Host $ScriptFullPath
