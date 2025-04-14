function Copy-CertifiCatSamples{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Intentionally leaving this plural, as this copies -all- sample files from the modules directory')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,
            HelpMessage="Specifies the directory into which the built-in CertifiCat sample files will be copied"
        )]
        [string] $outputDirectory,

        [Parameter(Mandatory=$false,
            HelpMessage="When this switch is present, any existing sample scripts of the same name in the output directory will be overwritten"
        )]
        [switch] $force,

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
        OutputDirectory = $outputDirectory;
        debugEnabled= $debugEnabled;
        debugLogDirectory = $debugLogDirectory;
        debugMode = $debugMode;
    }

    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Extracting sample scripts"

    "-> Checking for output directory '$outputDirectory'..." | Write-Host -NoNewLine

    if(Test-Path $outputDirectory){
        Write-Ok
    } else {
        Write-Pending
        "`tCreating new output directory..." | Write-Host -NoNewline
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null

        if(Test-Path $outputDirectory){
            Write-Ok
        } else {
            Write-Fail
            $fro.Errors = "Failed to create new output directory $outputDirectory"

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
            }
            return $fro
        }
    }

    "-> Copying sample scripts from module directory..." | Write-Host
    Get-ChildItem $PSModuleRoot\Samples | Foreach-Object {
        if($force){
            "`tForce-copying sample script '$($_.Name)'..." | Write-Host -NoNewline
            Copy-Item $_.FullName "$outputDirectory\" -Force
            if($?){
                Write-Ok
            } else {
                Write-Fail
                $fro.Errors += "Failed to copy sample script '$($_.Name)' from $PSModuleRoot\Samples to $outputDirectory"
                $fro.FunctionSuccess = $false
            }
        } else {
            "`tCopying sample script '$($_.Name)'..." | Write-Host -NoNewline
            if(Test-Path "$outputDirectory\$($_.Name)"){
                Write-Skipped
            } else {
                Copy-Item $_.FullName "$outputDirectory\"
                if($?){
                    Write-Ok
                } else {
                    Write-Fail
                    $fro.Errors += "Failed to copy sample script '$($_.Name)' from $PSModuleRoot\Samples to $outputDirectory"
                    $fro.FunctionSuccess = $false
                }
            }
        }
    }

    if($fro.FunctionSuccess){
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"
    } else {
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"
    }

    # write debug information if desired
    if($debugEnabled){
        Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
    }
    return $fro
}