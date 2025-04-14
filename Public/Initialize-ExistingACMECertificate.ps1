function Initialize-ExistingACMECertificate{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The only password used in this function is a certificate password, which is the well-known Posh-ACME default.')]
    param(
        [Parameter(Mandatory=$false,
            HelpMessage="When applied, this switch will attempt to update IIS HTTPS bindings"
        )]
        [switch] $UpdateBindings,

        [Parameter(Mandatory=$false,
            HelpMessage="Comma-separated list of posts on which to update bindings. When this parameter is omitted, all HTTPS-based bindings will be updated"
        )]
        [string[]] $BindingPorts,

        [Parameter(Mandatory=$false,
        HelpMessage="Specifies the Windows Certificate Store Name to import the resulting certificate into."
        )]
        [ValidateScript({if($_ -in $VALIDATE_SET_CERTIFICATE_STORE_NAME) { $true } else { throw "Parameter '$_' is invalid -- must be one of: $($VALIDATE_SET_CERTIFICATE_STORE_NAME -join ",")"}})]
        [string] $StoreName = $DEFAULT_CERTIFICATE_STORE_NAME,

        [Parameter(Mandatory = $false,
            HelpMessage = "Specified the Windows Certificate Store Location to import the resulting certificate into."
        )]
        [ValidateScript({if($_ -in $VALIDATE_SET_CERTIFICATE_STORE_LOCATION) { $true } else { throw "Parameter '$_' is invalid -- must be one of: $($VALIDATE_SET_CERTIFICATE_STORE_LOCATION -join ",")"}})]
        [string] $StoreLocation = $DEFAULT_CERTIFICATE_STORE_LOCATION,

        [Parameter (Mandatory = $true,
            HelpMessage = "Specify the full path to the PFX certificate file, including the filename itself."
        )]
        [ValidateScript({if($_ -match $VALIDATE_PATTERN_PFX_PATH) { $true } else { throw "Parameter '$_' is invalid -- must match the pattern: $VALIDATE_PATTERN_PFX_PATH"}})]
        $PfxPath,

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
        debugEnabled= $debugEnabled;
        debugLogDirectory = $debugLogDirectory;
        debugMode = $debugMode;
     }

    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Attempting to import Certificate"


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

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
     }

     # Ensure that the certificate file in question actually exists
     if(!(Test-Path $pfxPath)){
        Write-Fail

        "`tUnable to find certificate file: '$pfxPath' -- cannot continue!" | Write-Host -ForegroundColor Red -BackgroundColor Black
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "PFX certificate file not found in '$PfxPath"
        $fro.FunctionSuccess = $false
        $fro.BindingsUpdated = $false
        $fro.CertificateImported = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
     }

     Write-Ok

     Write-Host "-> Importing certificate into $StoreLocation\$StoreName..." -NoNewline

     # here we're assuming that this is a cert generated by Posh-ACME without a custom password
     $certPass = ConvertTo-SecureString "poshacme" -AsPlainText -Force

     $importedCert = Import-PfxCertificate -FilePath $PfxPath -CertStoreLocation "cert:\$StoreLocation\$StoreName" -Password $certPass -Exportable

    if($null -eq $importedCert){
        Write-Fail
        "`tAn error occurred while attempting to import the certificate. This could potentially be due to the certificate having a non-default PFX password."
        $fro.Errors += "PFX certificate file failed to import -- certificate file may be a non-Posh-ACME certificate, or have a non-standard password"
        $fro.FunctionSuccess = $false
        $fro.BindingsUpdated = $false
        $fro.CertificateImported = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
    } else {
        Write-Ok
        $fro.Certificate = $importedCert
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