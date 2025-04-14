function  Confirm-ACMERenewalReadiness {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true,
            HelpMessage = "Provide the CN/domain name of the certificate to check for"
        )]
        [string] $DomainName,

        [Parameter(Mandatory=$false,
            HelpMessage="Specifies the method by which the function will determine if a certificate needs renewal (PA for posh acme [default], IIS for IIS binding, Directory for specific directory)"
        )]
        [ValidateScript({if($_ -in $VALIDATE_SET_RENEWAL_METHOD) { $true } else { throw "Parameter '$_' is invalid -- must be one of: $($VALIDATE_SET_RENEWAL_METHOD -join ",")"}})]
        [string] $RenewalMethod = $DEFAULT_RENEWAL_METHOD,

        [Parameter(Mandatory=$false,
            HelpMessage="Specifies the directory in which to look for the existing certificate in the case of the RenewalMethod being set to Directory"
        )]
        [string] $RenewalDirectory = $DEFAULT_RENEWAL_DIRECTORY,

        [Parameter(Mandatory=$false,
            HelpMessage="Comma-separated list of posts on which to check bindings. When this parameter is omitted, all HTTPS-based bindings will be checked"
        )]
        [string[]] $BindingPorts,

        [Parameter(Mandatory=$false,
            DontShow = $true
        )]
        [switch] $ChainedCall,

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
        [string] $debugMode = $DEFAULT_DEBUG_MODE

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
        Bindings = @();
        Certificates = @();
        ReadyForRenewal = $false;
        RenewalThreshold = $RenewalThreshold;
        debugEnabled= $debugEnabled;
        debugLogDirectory = $debugLogDirectory;
        debugMode = $debugMode;
    }

    if(!($ChainedCall)){
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Looking for eligible certificates"

        # Check to ensure that we're running from an elevated PowerShell session
        if(!(Assert-AdminAccess)) {
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            $fro.Errors += "Session lacks administrative access. Ensure that PowerShell was run as an Administrator."
            $fro.FunctionSuccess = $false
            $fro.ReadyForRenewal = $false

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

            return $fro
        }

        Write-Host "-> Verifying the version of PowerShell being used..." -NoNewline

        # Check to see if we're using an IIS RenewalMethod, and if so, if we're running a modern (but unsupported) versino of powershell
        if(($RenewalMethod -eq "IIS") -and (!(Assert-PSVersion))){
            Write-Fail

            Write-Host "`tDetected this function running from a modern PowerShell console. This combination of parameters REQUIRES the use of PowerShell 6 or earlier. Check the 'PS5Command' property of the return object for a complete command to run instead." -ForegroundColor Red
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            $fro.Errors += "Function/parameters require PowerShell 6 or earlier, but running from a modern console. See the PS5Command property for a PowerShell 5 equivalent to run."
            $fro.FunctionSuccess = $false

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

            return $fro
        } else {
            Write-Ok
        }

        # Check to see if the renewal method is PA (Posh-ACME) and, if so, verify that Posh-ACME is actually available
        if($RenewalMethod -eq "PA"){
            Write-Host "-> Verifying that the Posh-ACME Module is installed and available..." -NoNewline

            if(!(Assert-PSACME)){
                Write-Fail

                Write-Host "`tCould not load the Posh-ACME module... was it installed in the CurrentUser scope instead of LocalMachine? Cannot continue!" -ForegroundColor Red
                Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

                $fro.Errors += "Posh-ACME module was not found -- it might be missing, or have been installed in the scope of a different user, rather than LocalMachine"
                $fro.FunctionSuccess = $false

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                }

                return $fro
            } else {
                Write-Ok
            }
        }

        Write-Host "-> Performing renewal check for primary domain '$DomainName' using the '$($RenewalMethod)' method..." -NoNewline
    }

    switch($RenewalMethod){
        "PA"{
            Write-Pending
            Write-Host "`tChecking Posh-ACME working directory for current certificates..." -NoNewline

            $existingCerts = Get-PACertificate $DomainName | Where-Object {$_.NotAfter -gt (Get-Date).AddDays($RenewalThreshold) }
            if($null -ne $existingCerts){
                Write-Fail
                Write-Host "`tAt least one valid certificate was found on this server that expires in $RenewalThreshold days or more. Renewal will not continue!" -ForegroundColor Yellow
                Write-Host "`tThe current certificate does not expire until: $($existingCerts[0].NotAfter)" -ForegroundColor Yellow

                if(!($ChainedCall)){
                    Write-Host "`nAt least one valid certificate was found -- renewal does not appear necessary!" -ForegroundColor Yellow
                    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"
                }

                $fro.ReadyForRenewal = $false
                $fro.Certificates = $existingCerts

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
                }

                return $fro
            } else {
                Write-Ok

                if(!($ChainedCall)){
                    Write-Host "`nRenewal does appear necessary at this time!" -ForegroundColor Yellow
                    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"
                }

                $fro.ReadyForRenewal = $true

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
                }

                return $fro
            }
        }

        "IIS"{
            Write-Pending
            if(($null -eq $BindingPorts) -or ($BindingPorts -eq "")){
                Write-Host "`tNo binding ports were specified with the -BindingPorts parameter...checking all HTTPS bindings..."
                $tgtBindings = get-webbinding -protocol "HTTPS"
                $existingCerts = @() #list of valid certificates found associated with the bindings that don't need to be renewed

                foreach($binding in $tgtBindings){
                    Write-Host "`t`tLooking for cert for binding on port $(($binding.bindinginformation -split ":")[1])..."
                    $tgtCert = get-webbinding -port ($binding.bindinginformation -split ":")[1] | foreach-object {get-childitem "cert:\localmachine\$($_.certificatestorename)\$($_.certificatehash)"} | Where-Object {$_.NotAfter -gt (Get-Date).AddDays($RenewalThreshold) -and $_.Subject -like "*$DomainName*"}

                    if($null -ne $tgtCert){
                        $existingCerts += $tgtCert
                    }
                }

                if($existingCerts.Count -gt 0){
                    Write-Host "`t`t`tAt least one certificate was found to still be valid. Renewal will not continue!" -ForegroundColor Yellow

                    if(!($ChainedCall)){
                        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"
                    }

                    $fro.ReadyForRenewal = $false
                    $fro.Certificates = $existingCerts
                    $fro.Bindings = $tgtBindings

                    # write debug information if desired
                    if($debugEnabled){
                        Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
                    }

                    return $fro
                }

            } else {
                #loop the list of ports
                $tgtBindings = @()
                $existingCerts = @()

                foreach($BindingPort in $BindingPorts){
                    Write-Host "`tLooking for cert for binding on port $($BindingPort.Trim())..."

                    $tgtBinding = get-webbinding -port $BindingPort.Trim()
                    $tgtCert = $tgtBinding | foreach-object {get-childitem "cert:\localmachine\$($_.certificatestorename)\$($_.certificatehash)"} | Where-Object {$_.NotAfter -gt (Get-Date).AddDays($RenewalThreshold) -and $_.Subject -like "*$DomainName*"}
                    $tgtBindings += $tgtBinding

                    if($tgtCert.Count -gt 0) { $existingCerts += $tgtCert }
                }

                if($existingCerts.Count -gt 0){
                    Write-Host "`tAt least one certificate was found to still be valid. Renewal will not continue!" -ForegroundColor Yellow

                    if(!($ChainedCall)){
                        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"
                    }

                    $fro.ReadyForRenewal = $false
                    $fro.Certificates = $existingCerts
                    $fro.Bindings = $tgtBindings

                    # write debug information if desired
                    if($debugEnabled){
                        Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
                    }

                    return $fro
                }
            }

            Write-Host "`tRenewal appears necessary at this time!" -ForegroundColor Yellow

            if(!($ChainedCall)){
                Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"
            }

            $fro.Certificates = $existingCerts
            $fro.Bindings = $tgtBindings
            $fro.ReadyForRenewal = $true

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
            }

            return $fro
        }

        "Directory"{
            Write-Pending

            Write-Host "`tValidating search directory '$($RenewalDirectory)'..." -NoNewline

            if(Test-Path $RenewalDirectory) {
                Write-Ok
            } else {
                Write-Fail

                Write-Host "`t`tThis is not a valid directory -- cannot determine if certificates are present. Renewal will not continue!" -ForegroundColor Red -BackgroundColor Black

                if(!($ChainedCall)){
                    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"
                }

                $fro.ReadyForRenewal = $false
                $fro.FunctionSuccess = $false
                $fro.Errors += "Invalid certificate directory ($RenewalDirectory) was specified. Directory was not found or access denied."

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                }

                return $fro
            }

            Write-Host "`tRecursively analyzing for current public key (*.cer) files in '$($RenewalDirectory)'..." -NoNewline

            $validCerts = @()

            Get-ChildItem $RenewalDirectory -Recurse -filter *.cer | ForEach-Object {
                $foundCert = new-object Security.Cryptography.X509Certificates.X509Certificate2 $_.FullName
                $validCerts += $foundCert
            }

            $validCerts = $validCerts | where-object {$_.issuer -like "*InCommon*" -and $_.notAfter -gt (get-date).AddDays($RenewalThreshold) -and $_.Subject -like "*$DomainName*"}
            $fro.Certificates = $validCerts

            if($validCerts.Count -gt 0){
                Write-Ok

                Write-Host "`t`tAt least one valid certificate was found -- renewal does not appear necessary!" -ForegroundColor Yellow
                if(!($ChainedCall)){
                    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"
                }

                $fro.ReadyForRenewal = $false

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
                }

                return $fro
            }else {
                Write-Ok
                if(!($ChainedCall)){
                    Write-Host "Renewal appears necessary at this time!" -ForegroundColor Yellow
                    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"
                }
                $fro.ReadyForRenewal = $true

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
                }
                return $fro
            }
        }
    }
}