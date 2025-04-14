function Write-Ok{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [CmdletBinding()]
    param()

    "ok" | Write-Host -ForegroundColor Green
}