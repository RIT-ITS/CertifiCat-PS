function Disable-ACMEProxyRedirect{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [CmdletBinding()]
    param(
        [Parameter (Mandatory = $false,
            HelpMessage = "The hostname of the server, on which the URL rewrite rule should be disabled. If empty, the current server is used."
        )]
        $TargetServer,

        [Parameter (Mandatory = $false,
            HelpMessage = "The name of the URL Rewrite rule for the ACME proxy redirect, to be disabled"
        )]
        $URLRewriteRuleName = $DEFAULT_URL_REWRITE_RULE_NAME,

        [Parameter (Mandatory = $false,
            HelpMessage = "The name of the IIS website containing the URL Rewrite Rule"
        )]
        $iisSiteName = $DEFAULT_IIS_WEBSITE,

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
        URLRewriteRuleName = $URLRewriteRuleName;
        AffectedServer = $TargetServer;
        DisabledSuccessfully = $true;
        URLRewriteRuleFound = $true;
        RemoteConnectionOK = $true;
        debugEnabled= $debugEnabled;
        debugLogDirectory = $debugLogDirectory;
        debugMode = $debugMode;
    }

    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Disabling ACME Proxy Redirect"

    # Check to see if we're running a modern (but unsupported) version of powershell
    Write-Host "-> Checking to ensure that we are running in a PowerShell 6 or earlier console..." -NoNewLine
    if((!(Assert-PSVersion))){
        Write-Fail

        Write-Host "`tDetected this function running from a modern PowerShell console. This combination of parameters REQUIRES the use of PowerShell 6 or earlier. Check the 'PS5Command' property of the return object for a complete command to run instead." -ForegroundColor Red
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "Function/parameters require PowerShell 6 or earlier, but running from a modern console. See the PS5Command property for a PowerShell 5 equivalent to run."
        $fro.FunctionSuccess = $false
        $fro.DisabledSuccessfully = $false
        $fro.URLRewriteRuleFound = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
    } else {
        Write-Ok
    }

    # calculate a simpler boolean to control whether we're running things locally or remotely
    if(($null -eq $TargetServer) -or ($TargetServer -eq "")){ $isLocal = $true } else { $isLocal = $false }

    # check to see if we're disabling on the current server and therefore need the shell to be run as admin
    if($isLocal){
        # check to ensure that the shell is running as admin
        if(!(Assert-AdminAccess)) {
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            $fro.Errors += "Session lacks administrative access. Ensure that PowerShell was run as an Administrator."
            $fro.FunctionSuccess = $false
            $fro.DisabledSuccessfully = $false
            $fro.URLRewriteRuleFound = $false

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

            return $fro
        }
    }

    # make the update
    $acmeStatus = Edit-ACMEProxyRedirect $TargetServer $URLRewriteRuleName $false $iisSiteName

    # check the results
    $fro.URLRewriteRuleFound = $acmeStatus.RuleFound
    $fro.RemoteConnectionOK = $acmeStatus.RemoteConnectionOK

    if(!$fro.RemoteConnectionOK){
        $fro.DisabledSuccessfully = $false
        $fro.FunctionSuccess = $false
        $fro.Errors += "Could not connect to remote server '$TargetServer' -- check to ensure the account running PowerShell, and that you aren't already in a remote session. Error is: $($acmeStatus.Errors)"

        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }
    } else {
        if(!$acmeStatus.RuleToggledSuccessfully){
            $fro.DisabledSuccessfully = $false
            $fro.FunctionSuccess = $false
            $fro.Errors += "Failed to disable URL Rewrite rule '$URLRewriteRuleName' in site '$iisSiteName'"

            if(!$fro.URLRewriteRuleFound){ $fro.errors += "Could not find URL rewrite rule '$URLRewriteRuleName' in site '$iisSiteName'"}

            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }
        } else {
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
            }
        }
    }

    return $fro
}