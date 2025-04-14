function Set-ACMEHome{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'TODO via issue #24: https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/24')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false,
            HelpMessage="Path to use as the Posh-ACME home directory"
        )]
        $paHome = $DEFAULT_POSHACME_HOME,

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

        [Parameter(Mandatory = $false, DontShow = $true)]
        [switch] $ChainedCall
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
        PAHome = '';
        PAHomeUpdated = $false;
        PAHomeCreated = $false;
        debugEnabled= $debugEnabled;
        debugLogDirectory = $debugLogDirectory;
        debugMode = $debugMode;
    }

	# Only print the header and check for admin if we are directly calling this function
    if(-not $chainedCall){
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Setting / Confirming Posh-ACME Home Directory"

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
	}

    Write-Host "-> Checking for existing POSHACME_HOME environment variable..." -NoNewline
    $exHome = [Environment]::GetEnvironmentVariable('POSHACME_HOME', 'Machine')

    #check to see if the POSHACME_HOME environment variable exists
    if($null -eq $exHome){
        # Add support for ShouldProcess / -WhatIf
        if($PSCmdlet.ShouldProcess(("Creating new POSHACME_HOME environment variable with target value {0}" -f $paHome), $paHome, "Set-ACMEHome")){
            # it does not -- create it new with the desired value
            Write-Pending
            Write-Host "`t-> Creating new POSHACME_HOME environment variable with target value ($paHome)..." -NoNewline
            [Environment]::SetEnvironmentVariable('POSHACME_HOME', $paHome, 'Machine')

            $exHome = [Environment]::GetEnvironmentVariable('POSHACME_HOME', 'Machine')
            if($exHome -eq $paHome){
                Write-Ok
                $fro.PAHome = $paHome
                $fro.PAHomeUpdated = $true
                $fro.PAHomeCreated = $true
            } else {
                Write-Fail
                $fro.PAHome = $exHome
                $fro.FunctionSuccess = $false
                $fro.Errors = "Failed to create / set new POSHACME_HOME System/Machine environment variable"
                Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                }

                return $fro
            }

            Write-Host "`t-> Creating ephemeral POSHACME_HOME variable for this session (so that we don't need to re-launch PowerShell)..." -NoNewline
            $env:POSHACME_HOME = $paHome

            if($env:POSHACME_HOME -eq $paHome){
                Write-Ok
            } else {
                Write-Fail
                Write-Host "`tPlease re-launch your PowerShell terminal to ensure that the new environment variable to picked up appropriately"
            }
        }
    } else {
        #it does exist -- need to check the value
        Write-Ok

        Write-Host "`t-> Verifying value of environment variable ($paHome)..." -NoNewline
        if($exHome -eq $paHome){
            Write-Ok
            $fro.PAHome = $exHome
        } else {
            if($PSCmdlet.ShouldProcess(("Updating value of POSHACME_HOME environment variable to {0}" -f $paHome), $paHome, "Set-ACMEHome")){
                # value doesn't match -- need to update
                Write-Pending
                Write-Host "`t-> Updating value of environment variable..." -NoNewline

                [Environment]::SetEnvironmentVariable('POSHACME_HOME', $paHome, 'Machine')

                $exHome = [Environment]::GetEnvironmentVariable('POSHACME_HOME', 'Machine')
                if($exHome -eq $paHome){
                    Write-Ok
                    $fro.PAHome = $paHome
                    $fro.PAHomeUpdated = $true
                } else {
                    Write-Fail
                    $fro.PAHome = $exHome
                    $fro.FunctionSuccess = $false
                    $fro.Errors = "Failed to update POSHACME_HOME System/Machine environment variable"
                    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

                    # write debug information if desired
                    if($debugEnabled){
                        Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                    }

                    return $fro
                }

                Write-Host "`t-> Creating ephemeral POSHACME_HOME variable for this session (so that we don't need to re-launch PowerShell)..." -NoNewline
                $env:POSHACME_HOME = $paHome

                if($env:POSHACME_HOME -eq $paHome){
                    Write-Ok
                } else {
                    Write-Fail
                    Write-Host "`tPlease re-launch your PowerShell terminal to ensure that the new environment variable to picked up appropriately"
                }
            }
        }
    }

    # check to ensure that the path specified as the posh-acme working directory exists
    Write-Host "-> Verify the presence of the Posh-ACME working directory..." -NoNewline
    if(Test-Path $paHome){
        Write-Ok

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
        }

    } else {
        if($PSCmdlet.ShouldProcess(("Creating working directory {0}" -f $paHome), $paHome, "Set-ACMEHome")){
            Write-Pending
            Write-Host "`t-> Creating working directory..." -NoNewline

            $nd = New-Item -ItemType Directory -Path $paHome
            if($null -ne $nd){
                Write-Ok

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
                }

            } else {
                Write-Fail
                $fro.Errors = "Failed to create directory for Posh-ACME: $paHome"
                $fro.FunctionSuccess = $false

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                }
                return $fro
            }
        }
    }

    # Force-reload the Posh-ACME module if needed
    # The primary use case here is in cases where a user calls this function directly
    # In the case of this function being called from Initialize-ACMEEnvironment, this will occur before we actually install Posh-ACME
    if($null -ne (Get-Module Posh-ACME)){
        Write-Host "-> Forcibly re-importing Posh-ACME to ensure that it picks up the new emphemeral variable value..."
        Remove-Module Posh-ACME -Force -ErrorAction SilentlyContinue
        Import-Module Posh-ACME -Force -Scope Global
    }

	if(-not $chainedCall){
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"
    }

    return $fro
}