function Install-PSACMEModule{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param()

    Write-Host "`t-> Installing Posh-ACME Module..." -NoNewline
    Install-Module -Name Posh-ACME -Scope AllUsers -Force
    if($null -ne (Get-Module -ListAvailable -Name Posh-ACME)){
        Write-Ok
        return $true
    } else {
        Write-Fail
        Write-Host "`tInstallation of the Posh-ACME module failed -- script cannot continue!"  -ForegroundColor Red -BackgroundColor Black
        return $false
    }
}