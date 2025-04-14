function Set-CertifiCatDomainValidation{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'TODO via issue #24: https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/24')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true,
            HelpMessage="Regular expression pattern to use as part of validating the SAN list of new certificate requests"
        )]
        $domainPattern,

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
        domainPattern = $domainPattern;
        debugEnabled= $debugEnabled;
        debugLogDirectory = $debugLogDirectory;
        debugMode = $debugMode;
    }

    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Configuring domain verification pattern"

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

    Write-Host "-> Checking for existing CERTIFICAT_VALIDATE_PATTERN_DOMAIN_NAME environment variable..." -NoNewline
    $exPattern = [Environment]::GetEnvironmentVariable('CERTIFICAT_VALIDATE_PATTERN_DOMAIN_NAME', 'Machine')

    #check to see if the CERTIFICAT_VALIDATE_PATTERN_DOMAIN_NAME environment variable exists
    if($null -eq $exPattern){
        # Add support for ShouldProcess / -WhatIf
        if($PSCmdlet.ShouldProcess(("Creating new CERTIFICAT_VALIDATE_PATTERN_DOMAIN_NAME environment variable with target value {0}" -f $domainPattern), $domainPattern, "Set-ACMEHome")){
            # it does not -- create it new with the desired value
            Write-Pending
            Write-Host "`t-> Creating new CERTIFICAT_VALIDATE_PATTERN_DOMAIN_NAME environment variable with target value..." -NoNewline
            [Environment]::SetEnvironmentVariable('CERTIFICAT_VALIDATE_PATTERN_DOMAIN_NAME', $domainPattern, 'Machine')

            $exPattern = [Environment]::GetEnvironmentVariable('CERTIFICAT_VALIDATE_PATTERN_DOMAIN_NAME', 'Machine')
            if($exPattern -eq $domainPattern){
                Write-Ok
            } else {
                Write-Fail
                $fro.FunctionSuccess = $false
                $fro.Errors = "Failed to create / set new CERTIFICAT_VALIDATE_PATTERN_DOMAIN_NAME System/Machine environment variable"
                Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                }

                return $fro
            }
        }
    } else {
        #it does exist -- need to check the value
        Write-Ok

        Write-Host "`t-> Verifying value of environment variable..." -NoNewline
        if($exPattern -eq $domainPattern){
            Write-Ok
        } else {
            if($PSCmdlet.ShouldProcess(("Updating value of CERTIFICAT_VALIDATE_PATTERN_DOMAIN_NAME environment variable to {0}" -f $domainPattern), $domainPattern, "Set-ACMEHome")){
                # value doesn't match -- need to update
                Write-Pending
                Write-Host "`t-> Updating value of environment variable..." -NoNewline

                [Environment]::SetEnvironmentVariable('CERTIFICAT_VALIDATE_PATTERN_DOMAIN_NAME', $domainPattern, 'Machine')

                $exPattern = [Environment]::GetEnvironmentVariable('CERTIFICAT_VALIDATE_PATTERN_DOMAIN_NAME', 'Machine')
                if($exPattern -eq $domainPattern){
                    Write-Ok
                } else {
                    Write-Fail
                    $fro.FunctionSuccess = $false
                    $fro.Errors = "Failed to update CERTIFICAT_VALIDATE_PATTERN_DOMAIN_NAME System/Machine environment variable"
                    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

                    # write debug information if desired
                    if($debugEnabled){
                        Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                    }

                    return $fro
                }
            }
        }
    }

	$Script:VALIDATE_PATTERN_DOMAIN_NAME = $domainPattern

	Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"

	# write debug information if desired
	if($debugEnabled){
		Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
	}

	return $fro
}