function Get-CertifiCatVariables{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Plural because we are initializing all variables at once')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [CmdletBinding()]
    param(
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

    # build a function return object
    $fro = [PSCustomObject]@{
        FunctionName = $myinvocation.MyCommand;
        RunningPSVersion = $PSVersionTable.PSVersion.ToString();
        PS5Command = $ps5Command;
        FunctionArguments = $functionArgs;
        FunctionSuccess = $true;
        Errors = @();
        debugEnabled= $debugEnabled;
        debugLogDirectory = $debugLogDirectory;
        debugMode = $debugMode;
        variableList = @()
    }

    # Dynamically read the module's definition (i.e. .psm1 file) and extract the default variables we find.
    # This eliminates the need to manually update this function with new default variables
    $varsToCheck = @()
    $foundVars = get-content "$PSModuleRoot\certificat-ps.psm1" | select-string "(\`$script:DEFAULT_(.)*)|(\`$script:VALIDATE_PATTERN(.)*)" -allmatches

    foreach($foundVar in $foundVars.Matches.Value){
        $varToCheck = ($foundVar -split " = ")[0]
        $varToCheck = ($varToCheck -split ":")[1]

        $varsToCheck += $varToCheck
    }

    # Add the Posh-ACME variable to the list too -- this isn't actually ours, but we should let folks now what its value is, if present
    $varsToCheck += "POSHACME_HOME"

    foreach($varToCheck in $varsToCheck){
		# check for the posh-acme environment variable -- this one isn't ours, so it doesn't follow our naming conventino
		if($varToCheck -eq "POSHACME_HOME"){
			if($null -ne (Get-Item "env:\POSHACME_HOME" -ErrorAction SilentlyContinue).Value){
				$varValue = [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent((Get-Item "env:\POSHACME_HOME" -ErrorAction SilentlyContinue).Value)
			} else {
                $varValue = $null
            }
		} else {
			if($null -ne (Get-Item "env:\CERTIFICAT_$varToCheck" -ErrorAction SilentlyContinue).Value){
				$varValue = [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent((Get-Item "env:\CERTIFICAT_$varToCheck" -ErrorAction SilentlyContinue).Value)
			} else {
				$varValue = (Get-Variable $varToCheck -Scope Script).Value
			}
		}

        $fro.variableList += @{$vartoCheck = $varValue}
    }

    # write debug information if desired
    if($debugEnabled){
        Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
    }

    return $fro
}
