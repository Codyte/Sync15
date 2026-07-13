@{
    # PSScriptAnalyzer settings do Sync Master
    # Uso: Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # Tool de console interativo: Write-Host e a saida intencional (cor/UX), nao logging.
        'PSAvoidUsingWriteHost'
        # Verbos PT-BR (Iniciar-/Criar-/Ativar-) sao a convencao do projeto; renomear quebra menus.
        'PSUseApprovedVerbs'
        'PSUseSingularNouns'
        # Funcoes de menu mudam estado por design; ShouldProcess poluiria a UX interativa.
        'PSUseShouldProcessForStateChangingFunctions'
    )
    # Regras de formatacao (indentacao/chaves) ficam fora do gate de lint —
    # pertencem a um passe de Invoke-Formatter, nao a deteccao de bugs.
}
