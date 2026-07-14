@echo off
rem Entrada dupla-clicavel e independente de pasta (%~dp0 = pasta deste .cmd).
rem Um .lnk NAO consegue referenciar a propria pasta, por isso este .cmd.
rem Prefere o powershell.exe do System32; se nao existir la, usa o do PATH.
rem O filho elevado pelo UAC sempre nasce em System32, entao o Set-Location
rem embutido garante que o script inicia na pasta deste .cmd.
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%PS%' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -Command ' + [char]34 + 'Set-Location -LiteralPath ''%~dp0''; & ''.\Sync_Master.ps1''' + [char]34) -Verb RunAs"
