function Initialize-NewACMECertificate{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    param(
        [Parameter(Mandatory=$true,
            Position=1,
            HelpMessage="Comma-separated list of hostnames to include in the certificate. The first in the list = the main domain; remaining domains = SANs"
        )]
        [string[]] $DomainList,

        [Parameter(Mandatory = $false,
            HelpMessage = "Specify the friendly name to assign to the certificate"
        )]
        $FriendlyName = "$(($DomainList[0] -split "\.")[0]) (Posh-ACME $(get-date -format "MM-dd-yyyy"))",

        [Parameter(Mandatory=$false,
            HelpMessage="When applied, this switch will attempt to update IIS HTTPS bindings"
        )]
        [switch] $UpdateBindings,

        [Parameter(Mandatory=$false,
            HelpMessage="Comma-separated list of posts on which to update bindings. When this parameter is omitted, all HTTPS-based bindings will be updated"
        )]
        [string[]] $BindingPorts,

        [Parameter(Mandatory=$false,
            HelpMessage="When applied, this switch will skip the import of the resulting certificate into the Windows Certificate Store"
        )]
        [switch] $SkipImport,

        [Parameter(Mandatory=$false,
            HelpMessage="Specifies the Windows Certificate Store Name to import the resulting certificate into. When omitted, this parameter defaults to WebHosting"
        )]
        [ValidateScript({if($_ -in $VALIDATE_SET_CERTIFICATE_STORE_NAME) { $true } else { throw "Parameter '$_' is invalid -- must be one of: $($VALIDATE_SET_CERTIFICATE_STORE_NAME -join ",")"}})]
        [string] $StoreName = $DEFAULT_CERTIFICATE_STORE_NAME,

        [Parameter(Mandatory = $false,
            HelpMessage = "Specified the Windows Certificate Store Location to import the resulting certificate into. When omitted, this defaults to LocalMachine."
        )]
        [ValidateScript({if($_ -in $VALIDATE_SET_CERTIFICATE_STORE_LOCATION) { $true } else { throw "Parameter '$_' is invalid -- must be one of: $($VALIDATE_SET_CERTIFICATE_STORE_LOCATION -join ",")"}})]
        [string] $StoreLocation = $DEFAULT_CERTIFICATE_STORE_LOCATION,

        [Parameter(Mandatory=$false,
            HelpMessage="When applied, the script will not copy the resulting certificate files to a central location on the server"
        )]
        [switch] $SkipCentralize,

        [Parameter(Mandatory=$false,
            HelpMessage="Specifies the directory into which the resulting certificate files will be copied."
        )]
        [string] $CentralDirectory = $DEFAULT_CENTRAL_DIRECTORY,

        [Parameter(Mandatory=$false,
            HelpMessage="When applied, this function will not attempt to check the expiration date of the newest ACME cert in the cache in an effort to minimize excessive renewals"
        )]
        [switch] $SkipRenewalCheck,

        [Parameter(Mandatory=$false,
            HelpMessage="Specifies the method by which the function will determine if a certificate needs renewal (PA for posh acme [default], IIS for IIS binding, Directory for specific directory)"
        )]
        [ValidateScript({if($_ -in $VALIDATE_SET_RENEWAL_METHOD) { $true } else { throw "Parameter '$_' is invalid -- must be one of: $($VALIDATE_SET_RENEWAL_METHOD -join ",")"}})]
        [string] $RenewalMethod = $DEFAULT_RENEWAL_METHOD,

        [Parameter(Mandatory=$false,
            HelpMessage="Specifies the directory in which to look for the existing certificate in the case of the RenewalMethod being set to Directory"
        )]
        [string] $RenewalDirectory = $DEFAULT_RENEWAL_DIRECTORY,

        [Parameter(Mandatory = $false,
            HelpMessage = "When set, the domains specified in the -DomainList parameter will not be verified to ensure that they match the established allowed domain format."
        )]
        [switch] $SkipDomainValidation,

        [Parameter(Mandatory=$false,
            HelpMessage = "Specify the number of days prior to expiration of the current certificate that should be used to determine whether or not a new certificate should be requested."
        )]
        $RenewalThreshold = $DEFAULT_RENEWAL_THRESHOLD,

        [Parameter(Mandatory = $false,
            HelpMessage = "Optionally write debug information about the function's execution to a file and/or the event log"
        )]
        [Switch] $debugEnabled,

        [Parameter(Mandatory = $false,
            HelpMessage = "Optionally specify a directory to write a debug log file to"
        )]
        [string] $debugLogDirectory = $DEFAULT_DEBUG_LOG_DIRECTORY,

        [Parameter(Mandatory = $false,
        HelpMessage = "Optionally specify whether to log to the windows event log (EVT), a file (file) or both (both)"
        )]
        [ValidateScript({if($_ -in $VALIDATE_SET_DEBUG_MODE) { $true } else { throw "Parameter '$_' is invalid -- must be one of: $($VALIDATE_SET_DEBUG_MODE -join ",")"}})]
        [string] $debugMode = $DEFAULT_DEBUG_MODE,

        [Parameter(Mandatory = $false,
            HelpMessage = "Optionally specify a maximum number of seconds the function will wait beforesending a command to Posh-ACME to order a new certificate. This is useful to introduce jitter and prevent overloading the ACME server when multiple servers are scheduled to renew certificates at the same time."
        )]
        $jitter = $DEFAULT_JITTER,

        [Parameter(Mandatory = $false,
            HelpMessage = "Specifies the certificate key size and type"
        )]
        [ValidateScript({if (($_ -ne "ec-256") -and ($_ -ne "ec-384") -and !(($_ -ge 2048) -and ($_ -le 4096) -and ($_ % 128 -eq 0))) { throw "Parameter '$_' is invalid -- must be 'ec-256', 'ec-384', or a value from 2048 - 4096 which is also divisible by 128"} else { $true } })]
        [string]$CertKeyLength = $DEFAULT_CERT_KEY_LENGTH,

        [Parameter(Mandatory = $false,
            ValueFromRemainingArguments = $true
        )]
        $otherACMEArgs
    )

    # check to see if the global debug environment variable is set
    if($null -ne $env:CERTIFICAT_DEBUG_ALWAYS){
        $debugEnabled = $true
    }

    # Build a complete command of all parameters being used to run this function
    $ps5Command = "powershell.exe {import-module CertifiCat-PS -Force; $($MyInvocation.MyCommand) "
    $functionArgs = ""
    foreach($a in $PSBoundParameters.Keys){
        if($PSBoundParameters[$a] -eq $true){
            $functionArgs += "-$a "
        } else {
            $functionArgs += "-$a `"$($PSBoundParameters[$a])`" "
        }
    }
    $ps5Command += ("$functionArgs}")

    #begin building the function's return object
    $fro = [PSCustomObject]@{
        FunctionName = $myinvocation.MyCommand;
        RunningPSVersion = $PSVersionTable.PSVersion.ToString();
        PS5Command = $ps5Command;
        FunctionArguments = $functionArgs;
        FunctionSuccess = $true;
        Errors = @();
        Certificate = @();
        Bindings = @();
        CertificateImported = $true;
        BindingsUpdated = $true;
        StoreLocation = $StoreLocation;
        StoreName = $StoreName;
        PFXPath = $PfxPath;
        ReadyForRenewal = $true;
        CertificateCentralized = $true;
        CentralDirectory = $CentralDirectory;
        CertificateFriendlyName = $FriendlyName;
        RenewalThreshold = $RenewalThreshold;
        debugEnabled= $debugEnabled;
        debugLogDirectory = $debugLogDirectory;
        debugMode = $debugMode;
        CertificateKeyLength = $CertKeyLength;
        MaxJitter = $jitter;
        ActualJitter = 0;
    }

    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Attempting to renew TLS Certificate"

    # Check to ensure that we're running from an elevated PowerShell session
    if(!(Assert-AdminAccess)) {
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "Session lacks administrative access. Ensure that PowerShell was run as an Administrator."
        $fro.FunctionSuccess = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
    }

    #######################################
    # Begin Parameter Pre-Fight Checks
    #######################################

    Write-Host "-> Verifying that the Posh-ACME Module is installed and available..." -NoNewline
    if(!(Assert-PSACME)){
        Write-Fail

        Write-Host "`tCould not load the Posh-ACME module... was it installed in the CurrentUser scope instead of LocalMachine? Cannot continue!" -ForegroundColor Red
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "Posh-ACME module was not found -- it might be missing, or have been installed in the scope of a different user, rather than LocalMachine"
        $fro.FunctionSuccess = $false
        $fro.BindingsUpdated = $false
        $fro.CertificateImported = $false
        $fro.CertificateCentralized = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
    } else {
        Write-Ok
    }

    Write-Host "-> Validating incoming parameters..." -NoNewline

    # Check to see if we're going to update bindings, and, if so, if we're running in a modern (but unsupported) version of PowerShell
    if(($UpdateBindings) -and (!(Assert-PSVersion))){
        Write-Fail

        Write-Host "`tDetected this function running from a modern PowerShell console. This combination of parameters REQUIRES the use of PowerShell 6 or earlier. Check the 'PS5Command' property of the return object for a complete command to run instead." -ForegroundColor Red
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "Function/parameters require PowerShell 6 or earlier, but running from a modern console. See the PS5Command property for a PowerShell 5 equivalent to run."
        $fro.FunctionSuccess = $false
        $fro.BindingsUpdated = $false
        $fro.CertificateImported = $false
        $fro.CertificateCentralized = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
    }

    # Check to see if we're using an IIS RenewalMethod, and if so, if we're running a modern (but unsupported) version of powershell
    if(($RenewalMethod -eq "IIS") -and (!(Assert-PSVersion))){
        Write-Fail

        Write-Host "`tDetected this function running from a modern PowerShell console. This combination of parameters REQUIRES the use of PowerShell 6 or earlier. Check the 'PS5Command' property of the return object for a complete command to run instead." -ForegroundColor Red
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "Function/parameters require PowerShell 6 or earlier, but running from a modern console. See the PS5Command property for a PowerShell 5 equivalent to run."
        $fro.FunctionSuccess = $false
        $fro.BindingsUpdated = $false
        $fro.CertificateImported = $false
        $fro.CertificateCentralized = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
    }

     # Check to make sure we aren't attempting to update binding(s) with a certificate that's being imported into the CurrentUser store
     if(($UpdateBindings) -and $($StoreLocation -ne "LocalMachine")){
        Write-Fail

        "`tWhen the -UpdateBindings switch is applied to this function, the -StoreLocation parameter MUST be LocalMachine!" | Write-Host -ForegroundColor Red -BackgroundColor Black
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "UpdateBindings switch applied, but -StoreLocation parameter set to $StoreLocation. To update Site bindings, StoreLocation MUST be LocalMachine"
        $fro.FunctionSuccess = $false
        $fro.BindingsUpdated = $false
        $fro.CertificateImported = $false
        $fro.CertificateCentralized = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
     }

    # Check to ensure that we aren't attempting to update IIS bindings but skipping the import into the cert store
    if(($UpdateBindings) -and ($SkipImport)){
        Write-Fail

        "`tWhen the -UpdateBindings switch is applied to this function, you cannot also specify the -SkipImport switch!" | Write-Host -ForegroundColor Red -BackgroundColor Black
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "UpdateBindings and SkipImport switches both specified -- When UpdateBindings is specified, SkipImport must NOT be present"
        $fro.FunctionSuccess = $false
        $fro.BindingsUpdated = $false
        $fro.CertificateImported = $false
        $fro.CertificateCentralized = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
    }

    # Validate the domain names to ensure that they match the allowed pattern, unless we are specifically bypassing this check
    $invalidDomains = @()

    foreach($domain in $DomainList){
        if(!($domain -match $VALIDATE_PATTERN_DOMAIN_NAME)){
            $invalidDomains += $domain
        }
    }

    if(($invalidDomains.Count -gt 0) -and (!($SkipDomainValidation))){
        Write-Fail

        "`tDetected $($invalidDomains.Count) domains in the certificate request that do not meet the the domain name pattern '$VALIDATE_PATTERN_DOMAIN_NAME': ($($invalidDomains -join ',')). Add the -SkipDomainValidation switch to override this check." | Write-Host -ForegroundColor Red -BackgroundColor Black
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "-SkipDomainValidation switch was not specified, but detected the following non-conforming domains in the certificate request: $($invalidDomains -join ","). Domains must match the pattern: '$VALIDATE_PATTERN_DOMAIN_NAME'"
        $fro.FunctionSuccess = $false
        $fro.BindingsUpdated = $false
        $fro.CertificateImported = $false
        $fro.CertificateCentralized = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
    }

    # validate the -CertKeyLength parameter... the ValidateScript directive will take care of some of this, but this serves as an additional double check if the default value was overwritten via an environment variable
    if (($CertKeyLength -ne "ec-256") -and ($CertKeyLength -ne "ec-384") -and !(($CertKeyLength -ge 2048) -and ($CertKeyLength -le 4096) -and ($CertKeyLength % 128 -eq 0))) {
        Write-Fail

        "`tThe -CertKeyLength parameter is not a valid value. It must be 'ec-256', 'ec-384', or a value from 2048 - 4096 which is also divisible by 128. However, the value '$CertKeyLength' was provided." | Write-Host -ForegroundColor Red -BackgroundColor Black
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "Invalid value for -CertKeyLength provided ('$CertKeyLength') -- must be 'ec-256', 'ec-384', or a value from 2048 - 4096 which is also divisible by 128"
        $fro.FunctionSuccess = $false
        $fro.BindingsUpdated = $false
        $fro.CertificateImported = $false
        $fro.CertificateCentralized = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
    }

    Write-Ok

    # Check to see if the SkipCentralize switch is applied alongside a custom CentralDirectory parameter
    # (We'll just warn the user and ignore the CentralDirectory param -- we won't do a hard-stop)
    if(($SkipCentralize) -and ($CentralDirectory -ne $DEFAULT_CENTRAL_DIRECTORY)){
        Write-Host "`tWARNING: Ignoring the -CentralDirectory parameter value due to the presence of the -SkipCentralize parameter!" -ForegroundColor Yellow -BackgroundColor Black
    }

    # Check to see if the -BindingPorts parameter is populated, without the -UpdateBindings switch
    # (We'll just warn the user and ignore the binding updates -- we won't do a hard-stop)
    if(($BindingPorts -ne "") -and ($null -ne $BindingPorts) -and (!$UpdateBindings)){
        "`tWARNING: The -BindingPorts parameter was populated, but the -UpdateBindings switch was not specified! Bindings WILL NOT be updated automatically!" | Write-Host -ForegroundColor Yellow
    }

    # Update the certificate central directory with the primary domain name and timestamp
    $centralDirectory = "$centralDirectory\$($DomainList[0])\$(get-date -format "MM-dd-yyyy-HH-mm-ss")"

    # Parse the remaining arguments that were passed in that should be passed to Posh-ACME
     $otherArgsSplat = @{
    }

    for($argNum = 0; $argNum -lt $otherACMEArgs.Count; $argNum++){
        if((($otherACMEArgs[($argNum + 1)]) -Match "^-") -or ($null -eq $otherACMEArgs[($argNum + 1)])){
            $otherArgsSplat.Add($otherACMEArgs[$argNum], $true)
        } else {
            $otherArgsSplat.Add($otherACMEArgs[$argNum], $otherACMEArgs[($argNum+1)])
            $argNum += 1
        }
    }

    #######################################
    # End Parameter Pre-Fight Checks
    #######################################

    # Check to see if we need to even attempt a certificate renewal
    $tgtDomain = ($DomainList -split ",")[0]
    Write-Host "-> Performing renewal check for primary domain '$tgtDomain' using the '$($RenewalMethod)' method..." -NoNewline

    if(!($SkipRenewalCheck)){
        $canContinue = Confirm-ACMERenewalReadiness -ChainedCall -DomainName $tgtDomain -RenewalMethod $RenewalMethod -RenewalDirectory $RenewalDirectory -BindingPorts $BindingPorts -RenewalThreshold $RenewalThreshold

        if($canContinue.ReadyForRenewal -ne $true){
            Write-Host "`nAt least one valid certificate was found -- renewal will not continue! To force a renwal, use the -SkipRenewalCheck switch." -ForegroundColor Yellow

            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"

            $fro.BindingsUpdated = $false
            $fro.CertificateImported = $false
            $fro.CertificateCentralized = $false
            $fro.CentralDirectory = ""
            $fro.ReadyForRenewal = $false

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
            }

            return $fro
        }
    } else {
        Write-Skipped
    }

    # We are going to request a new certificate at this point -- check to see if we need to introduce jitter
    if(($null -ne $jitter) -and ($jitter -gt 0)){
        $jitter = Get-Random -Minimum 1 -Maximum $jitter

        # capture the actual jitter value we're using so that the user knows how long we actual waited
        $fro.ActualJitter = $jitter

        Write-Host "-> Pausing for $jitter seconds to introduce jitter and prevent too many simultaneous certificate requests across the environment..."
        Start-Sleep -Seconds $jitter
    }


    Write-Host "-> Requesting new certificate from ACME server..." -NoNewline

    $cert = New-PACertificate -Domain $DomainList -FriendlyName $FriendlyName -Plugin WebSelfHost -Force -AlwaysNewKey -CertKeyLength $CertKeyLength @otherArgsSplat

    if($null -eq $cert){
        Write-Fail

        Write-Host "`tAn error occurred while attempting to request the new certificate -- script will not continue!" -ForegroundColor Red -BackgroundColor Black
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.FunctionSuccess = $false
        $fro.BindingsUpdated = $false
        $fro.CertificateImported = $false
        $fro.CertificateCentralized = $false
        $fro.Errors += "Error occurred attempting to obtain new Posh-ACME certificate"

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro

    } else {
        Write-Ok
    }

    # copy the certificate to a central location, if needed
    $CertCurrentDirectory = $cert.certfile.replace("cert.cer", "")

    if($SkipCentralize){
        Write-Skipped
        $fro.PFXPath = "$CertCurrentDirectory\cert.pfx"
    } else {
        $centralizedOK = Copy-CertificateToCentralDirectory $CentralDirectory $CertCurrentDirectory
        switch($centralizedOK){
            "directory"{
                Write-Host "`t`tAn error occurred creating new directory -- copy cannot continue!" -ForegroundColor Red

                $fro.FunctionSuccess = $false
                $fro.BindingsUpdated = $false
                $fro.CertificateImported = $false
                $fro.CertificateCentralized = $false
                $fro.Errors += "Error occurred attempting to create central directory '$CentralDirectory'"

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                }

                return $fro
            }

            "copy"{
                Write-Host "`t`tDue to a failure copying the certificate files, we won't proceed with any additional actions!" -ForegroundColor Red

                $fro.FunctionSuccess = $false
                $fro.BindingsUpdated = $false
                $fro.CertificateImported = $false
                $fro.CertificateCentralized = $false
                $fro.Errors += "Error occurred attempting to copy certificate files from '$CertCurrentDirectory' to '$CentralDirectory'"

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                }

                return $fro
            }

            default{
                $fro.PFXPath = "$CentralDirectory\cert.pfx"
            }
        }
    }

    # import the resultant certificate into the windows certificate store
    Write-Host "-> Importing certificate into the $StoreLocation\$StoreName Store..." -NoNewline
    if($SkipImport){
        Write-Skipped
    } else {
        Install-PACertificate $cert -StoreLocation $StoreLocation -StoreName $StoreName

        #make sure we imported the certificate successfully
        $importedCert = get-item "cert:\$StoreLocation\$StoreName\$($cert.thumbprint)"

        if($null -ne $importedCert){
            Write-Ok
            $fro.Certificate = $importedCert
        } else {
            Write-Fail
            Write-Host "`tDue to a failure importing the new certificate into the certificate store, we won't proceed with any additional actions!" -ForegroundColor Red

            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            $fro.FunctionSuccess = $false
            $fro.BindingsUpdated = $false
            $fro.CertificateImported = $false
            $fro.CertificateCentralized = $false
            $fro.Errors += "Error occurred attempting to import new certificate into cert:\$CertLocation\$CertStore"

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

            return $fro
        }
    }

     # check to see if we're going to update IIS bindings
     Write-Host "-> Updating IIS Site Bindings..." -NoNewLine
     if($UpdateBindings){
         Write-Pending
         $updatedBindings = Update-IISBindings $BindingPorts $StoreName $importedCert.Thumbprint

         #remove the phantom $nulls appearing in the list
         $updatedBindings = $updatedBindings | where-object {$_ -ne $Null }
         $fro.Bindings = $updatedBindings

         if(($updatedBindings | Where-Object {$_.UpdatedSuccessfully -eq $false}).Count -eq 0){
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
            }

            return $fro
         } else {
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            $fro.Errors += "Error(s) occurred updating one or more bindings. Please review the Bindings property of this return object for more details."
            $fro.BindingsUpdated = $false

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

            return $fro
         }

     } else {
        Write-Skipped
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"
        $fro.BindingsUpdated = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
        }

        return $fro
     }
}
