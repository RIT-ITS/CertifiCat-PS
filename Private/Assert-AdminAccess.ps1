# Based off of the learn.microsoft.com article on "A self elevating PowerShell script"
# https://learn.microsoft.com/en-us/archive/blogs/virtual_pc_guy/a-self-elevating-powershell-script
function Assert-AdminAccess{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [OutputType([System.Boolean])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch] $hideOutput
    )

    if(!($hideOutput)){
        Write-Host "-> Confirming that we are in an admin session..." -NoNewline
    }

    # Get the ID and security principal of the current user account
    $myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
    $myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)

    # Get the security principal for the Administrator role
    $adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator

    # Check to see if we are currently running "as Administrator"
    if (!($myWindowsPrincipal.IsInRole($adminRole)))
    {
        if(!($hideOutput)){
            Write-Fail
            Write-Host "`tPlease ensure that this PowerShell terminal was explicitly run as an Administrator -- cannot continue!" -ForegroundColor Red -BackgroundColor Black
        }

        return $false
    } else
    {
        if(!($hideOutput)) { Write-Ok }
        return $true
    }
}