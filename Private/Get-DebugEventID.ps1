function Get-DebugEventID{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('InjectionRisk.StaticPropertyInjection', '',
    Justification = 'No concern with possible static injection of variables here exposing information in the functionEventIDs because
    (a) this is a private function that we control the parameter values as it is called, and
    (b) even if a "malicious" value is passed, the array contains no "sensitive" or protected values. The worst case scenario is that the wrong Event ID is returned')]

    [CmdletBinding()]

    param(
        [Parameter(Mandatory = $true)]
        [string] $callingFunction,

        [Parameter(Mandatory = $true)]
        [Boolean] $functionSucceeded
    )

    $functionEventIDs = @{
        "Assert-SiteCertificate" = @{ $true = 1001; $false = 2001 };
        "Confirm-ACMERenewalReadiness" = @{ $true = 1002; $false = 2002 };
        "Disable-ACMEProxyRedirect" = @{ $true = 1003; $false = 2003 };
        "Enable-ACMEProxyRedirect" = @{ $true = 1004; $false = 2004 };
        "Get-CertifiCatVariables" = @{ $true = 1007; $false = 2007 };
        "Initialize-ACMEEnvironment" = @{ $true = 1005; $false = 2005 };
        "Initialize-ACMEProxyRedirect" = @{ $true = 1006; $false = 2006 };
        "Initialize-ExistingACMECertificate" = @{ $true = 1008; $false = 2008 };
        "Initialize-NewACMECertificate" = @{ $true = 1009; $false = 2009 };
        "Repair-NewACMEOrder" = @{ $true = 1010; $false = 2010 };
        "Set-ACMEHome" = @{ $true = 1011; $false = 2011 };
        "Copy-CertifiCatSamples" = @{ $true = 1012; $false = 2012 };

    }

    # make sure that there is an event id defined above for the calling function
    # practically speaking, this should always be the case, but error handling is good, in the off-chance that we forget to update the array
    if($null -eq $functionEventIDs.$callingFunction.$functionSucceeded){
        return $null
    } else {
        return $functionEventIDs.$callingFunction.$functionSucceeded
    }
}