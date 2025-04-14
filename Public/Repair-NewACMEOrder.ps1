function Repair-NewACMEOrder{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    param(

        [Parameter (Mandatory = $true,
            HelpMessage = "The primary / main domain associated with the ACME Order"
        )]
        $MainDomain,

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
            HelpMessage="Specifies the directory in which the resulting certificate files will be copied."
        )]
        [string] $CentralDirectory = $DEFAULT_CENTRAL_DIRECTORY,

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
        Certificate = @();
        Bindings = @();
        CertificateImported = $true;
        BindingsUpdated = $true;
        StoreLocation = $StoreLocation;
        StoreName = $StoreName;
        PFXPath = $PfxPath;
        CertificateCentralized = $true;
        CentralDirectory = $CentralDirectory;
        CertificateFriendlyName = "";
        debugEnabled= $debugEnabled;
        debugLogDirectory = $debugLogDirectory;
        debugMode = $debugMode;
    }

    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Attempting to repair open ACME order"

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

    #######################################
    # End Parameter Pre-Fight Checks
    #######################################

    # check to see if the status of the current order is valid
    Write-Host "-> Querying ACME Server for Current order status..." -NoNewline

    $activeOrder = Get-PAOrder -MainDomain $MainDomain -Refresh

    # add the certificate / order's friendlyname to the return object
    $fro.CertificateFriendlyName = $activeOrder.FriendlyName

	switch($activeOrder.Status){
		"processing"{
			Write-Fail
			Write-Host "`tActive order is still being processed by the ACME server - please try again later" -ForegroundColor Red

			$fro.FunctionSuccess = $false
			$fro.BindingsUpdated = $false
			$fro.CertificateImported = $false
			$fro.CertificateCentralized = $false
			$fro.Errors += "Active order is still being processed by the ACME server - please try again later"

            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

			return $fro
		}
		"valid"{
			Write-Ok
		}
		default{
			Write-Fail
			Write-Host "`tActive order is in a status we aren't expecting (status = $($activeOrder.Status))" -ForegroundColor Red

			$fro.FunctionSuccess = $false
			$fro.BindingsUpdated = $false
			$fro.CertificateImported = $false
			$fro.CertificateCentralized = $false
			$fro.Errors += "Active order is in a status we aren't expecting (status = $($activeOrder.Status))"

            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            # write debug information if desired
            if($debugEnabled){
               Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

			return $fro
		}
	}

    Write-Host "-> Completing ACME Order..." -NoNewLine
    $cert = Complete-PAOrder

    if($null -ne $cert.Thumbprint){
        Write-Ok
    } else {
        Write-Fail
        Write-Host "`t`tFailed to complete ACME order -- no certificate was returned" -ForegroundColor Red

        $fro.FunctionSuccess = $false
        $fro.BindingsUpdated = $false
        $fro.CertificateImported = $false
        $fro.CertificateCentralized = $false
        $fro.Errors += "Failed to complete ACME order -- no certificate was returned"

        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
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

                Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

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

                Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

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
        # use the Posh-ACME function to do the heavy lifting here
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