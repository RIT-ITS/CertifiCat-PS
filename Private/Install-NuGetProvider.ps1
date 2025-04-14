function Install-NuGetProvider{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param()

    Write-Host "`t`t-> Installing NuGet Package Provider..." -NoNewline
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null

    if($null -eq (Get-PackageProvider -ListAvailable NuGet -ErrorAction SilentlyContinue)){
        Write-Fail
        Write-Host "`t`tInstallation of the NuGet package provider failed -- script cannot continue!" -ForegroundColor Red -BackgroundColor Black
        return $false
    } else {
        Write-Ok
        return $true
    }
}