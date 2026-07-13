param(
    [string]$ShortcutName = "Sync Master",
    [string]$ScriptPath = ".\Sync_Master.ps1",
    [string]$ShortcutDirectory = "$env:USERPROFILE\Desktop",
    [switch]$RunAsAdmin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-FullPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $Path))
}

$ScriptFullPath = Resolve-FullPath -Path $ScriptPath

if (-not (Test-Path -LiteralPath $ScriptFullPath -PathType Leaf)) {
    throw "Script não encontrado: $ScriptFullPath"
}

$WorkingDirectory = Split-Path -Parent $ScriptFullPath

$PwshPath = Get-Command pwsh.exe -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty Source

if (-not $PwshPath) {
    $PwshPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
}

if (-not (Test-Path -LiteralPath $PwshPath -PathType Leaf)) {
    throw "PowerShell não encontrado."
}

if (-not (Test-Path -LiteralPath $ShortcutDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null
}

$ShortcutPath = Join-Path $ShortcutDirectory "$ShortcutName.lnk"

$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)

if ($RunAsAdmin) {
    $Shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    $escapedPwsh = $PwshPath.Replace("'", "''")
    $escapedScript = $ScriptFullPath.Replace("'", "''")
    $escapedWorkingDir = $WorkingDirectory.Replace("'", "''")

    $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"Start-Process -FilePath '$escapedPwsh' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `"$escapedScript`"' -WorkingDirectory '$escapedWorkingDir' -Verb RunAs`""
} else {
    $Shortcut.TargetPath = $PwshPath
    $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptFullPath`""
}

$Shortcut.WorkingDirectory = $WorkingDirectory
$Shortcut.WindowStyle = 1
$Shortcut.Description = "Executar Sync Master"
$Shortcut.IconLocation = "$PwshPath,0"
$Shortcut.Save()

Write-Host "Atalho criado em:" -ForegroundColor Green
Write-Host $ShortcutPath
Write-Host ""
Write-Host "Script alvo:" -ForegroundColor Cyan
Write-Host $ScriptFullPath
Write-Host ""
Write-Host "PowerShell usado:" -ForegroundColor Cyan
Write-Host $PwshPath

if ($RunAsAdmin) {
    Write-Host ""
    Write-Host "Modo administrador ativado. O Windows solicitará confirmação do UAC ao abrir o atalho." -ForegroundColor Yellow
}
