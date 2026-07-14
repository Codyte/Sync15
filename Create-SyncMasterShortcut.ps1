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

# O alvo é sempre o Windows PowerShell 5 (caminho fixo em todo Windows); a PARTE 1.1
# do Sync_Master.ps1 relança em pwsh sozinha. Assim o .lnk não depende de onde
# (ou se) o PS7 está instalado.
$Ps5Path = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

if (-not (Test-Path -LiteralPath $ShortcutDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null
}

# O .lnk grava caminho ABSOLUTO por necessidade: um atalho não conhece a própria
# pasta em runtime ("Iniciar em" vazio → CWD = System32). Entrada independente de
# pasta é o "Sync Master.cmd" (usa %~dp0), não este gerador.
$ScriptRef  = $ScriptFullPath
$LnkWorkDir = $WorkingDirectory

$ShortcutPath = Join-Path $ShortcutDirectory "$ShortcutName.lnk"

$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)

$Shortcut.TargetPath = $Ps5Path

if ($RunAsAdmin) {
    # [char]34 evita aspas duplas aninhadas (CommandLineToArgvW as remove/mangleia).
    $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"Start-Process powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File ' + [char]34 + '$ScriptRef' + [char]34) -Verb RunAs`""
} else {
    $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptRef`""
}

$Shortcut.WorkingDirectory = $LnkWorkDir
$Shortcut.WindowStyle = 1
$Shortcut.Description = "Executar Sync Master"
$Shortcut.IconLocation = "$Ps5Path,0"
$Shortcut.Save()

Write-Host "Atalho criado em:" -ForegroundColor Green
Write-Host $ShortcutPath
Write-Host ""
Write-Host "Script alvo:" -ForegroundColor Cyan
Write-Host $ScriptRef

if ($RunAsAdmin) {
    Write-Host ""
    Write-Host "Modo administrador ativado. O Windows solicitará confirmação do UAC ao abrir o atalho." -ForegroundColor Yellow
}
