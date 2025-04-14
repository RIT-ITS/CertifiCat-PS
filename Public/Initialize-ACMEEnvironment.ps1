function Initialize-ACMEEnvironment{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false,
            HelpMessage="ACME Server to Connect to."
        )]
        [string] $ACMEServer = $DEFAULT_ACME_SERVER,

        [Parameter(Mandatory = $false,
            HelpMessage="ID value from the ACME server to use during account setup"
        )]
        [string] $PAUserID,

        [Parameter(Mandatory = $false,
            HelpMessage="Key value from the ACME server to use during account setup"
        )]
        [string] $PAUserKey,

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
            HelpMessage="Path to use as the Posh-ACME home directory"
        )]
        $paHome = $DEFAULT_POSHACME_HOME

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
        EnvironmentSetupSuccessfully = $true;
        PoshACMEAccount = $null;
        ACMEServerURL = $ACMEServer;
        debugEnabled= $debugEnabled;
        debugLogDirectory = $debugLogDirectory;
        debugMode = $debugMode;
        PAHome = '';
        PAHomeUpdated = $false;
        PAHomeCreated = $false;
    }

    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Setting up Posh-ACME on this server"

    # check to ensure that the shell is running as admin
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

    # Call Set-ACMEHome so that we can update the Posh-ACME working directory
    Write-Host "-> Calling Set-ACMEHome to set the new central working directory..."
	Write-Host "-------------------------------------------------------------------"
    $newHome = Set-ACMEHome -paHome $paHome -ChainedCall
	Write-Host "-------------------------------------------------------------------"

	if($newHome.FunctionSuccess){
        $fro.PAHome = $paHome
        $fro.PAHomeCreated = $newHome.PAHomeCreated
        $fro.PAHomeUpdated = $newHome.PAHomeUpdated
    } else {
        $fro.FunctionSuccess = $false
        $fro.Errors += $newHome.Errors

        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
        }

        return $fro
    }

    Write-Host "-> Checking for Posh-ACME Module..." -NoNewline
    if($null -ne (Get-Module -ListAvailable -Name Posh-ACME)){
        #Posh-ACME is already installed
        Write-Ok
    } else {
        #Posh-ACME is not yet installed
        Write-Pending
        Write-Host "`t-> Checking for NuGet Provider (required to interact with PSGallery)..." -NoNewline
        if($null -eq (Get-PackageProvider -ListAvailable NuGet -ErrorAction SilentlyContinue)){
            #NuGet is not configured
            Write-Pending
            if(!(Install-NuGetProvider)) {
                #NuGet failed to install
                $fro.FunctionSuccess = $false
                $fro.EnvironmentSetupSuccessfully = $false
                $fro.Errors += "Error occurred attempting to install NuGet Provider. Command attempting to execute was: 'Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force'"

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                }

                return $fro
            }
            if(!(Install-PSAcmeModule)) {
                #Posh-ACME failed to install
                $fro.FunctionSuccess = $false
                $fro.EnvironmentSetupSuccessfully = $false
                $fro.Errors += "Error occurred attempting to install Posh-ACME module. Command attempting to execute was: 'Install-Module -Name Posh-ACME -Force'"

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                }

                return $fro
             }

        } else {
            #NuGet is configured, but Posh-ACME is not installed
            Write-Ok
            if(!(Install-PSAcmeModule)) {
                #Posh-ACME failed to install
                $fro.FunctionSuccess = $false
                $fro.EnvironmentSetupSuccessfully = $false
                $fro.Errors += "Error occurred attempting to install Posh-ACME module. Command attempting to execute was: 'Install-Module -Name Posh-ACME -Force'"

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                }

                return $fro
            }
        }
    }

    Write-Host "-> Setting ACME server to '$acmeServer'..." -NoNewline
    if(($null -ne (Get-PAServer).Location) -and ((Get-PAServer).Location -eq $ACMEServer)){
        Write-Ok
        $fro.ACMEServerURL = $ACMEServer
    } else {
        Set-PAServer $acmeServer
        if((Get-PAServer).location) {
            Write-Ok
            $fro.ACMEServerURL = $ACMEServer
        } else {
            Write-Fail

            $fro.FunctionSuccess = $false
            $fro.EnvironmentSetupSuccessfully = $false
            $fro.Errors += "Unable to set Posh-ACME server to '$acmeServer'"

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

            return $fro
        }
    }
    Write-Host "-> Checking for ACME account..." -NoNewline
    $paAccount = Get-PAAccount -List

    if($null -eq ($paAccount)){
        Write-Pending

        if(('' -eq $paUserID) -or ('' -eq $paUserKey)){
            Write-Host "`tAn existing Posh-ACME account was not found for this server."
            Write-Host "`tIn order to complete the initialization process, an account must be added to this server."
            Write-Host "`tYou will need the 'External Account ID' and 'External Account Key' values from the ACME server to continue."
            Write-Host "`n`tIf you are not ready to continue, you can re-run this function again at a later time."

            $setupReady = Read-Host "`n`tAre you ready to continue the setup process (y)?"

            if($setupReady -ne 'y'){
                $fro.Errors += "User cancelled setup process"
                $fro.EnvironmentSetupSuccessfully = $false
				$fro.FunctionSuccess = $false

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                }

				Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

                return $fro
            } else {
                $paUserID = Read-Host "`n`tExternal Account ID"
                $paUserKey = Read-Host "`tExternal Account Key"
            }
        }

        $paAccount = Add-PAAccount $paUserID $paUserKey
        if($null -ne $paAccount) {
            $fro.PoshACMEAccount = $paAccount
        } else {
            $fro.EnvironmentSetupSuccessfully = $false
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
            }

            return $fro
        }
    } else {
        Write-Ok
        $fro.PoshACMEAccount = $paAccount
    }


    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"

    # write debug information if desired
    if($debugEnabled){
        Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
    }

    return $fro
}