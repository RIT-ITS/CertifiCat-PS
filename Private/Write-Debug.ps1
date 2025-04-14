function Write-ACMEDebug{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('InjectionRisk.StaticPropertyInjection', '', Justification = 'No concern with dynamic member access here -- this is being flagged due to our
    reading of the function return object ($fro) to enumerate properties containing object arrays on/around line 39')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $callingFunction,

        [Parameter(Mandatory = $true)]
        $fro,

        [Parameter(Mandatory = $true)]
        [Boolean] $functionSucceeded,

        [Parameter(Mandatory = $false)]
        [string] $debugMode = $DEFAULT_DEBUG_MODE,

        [Parameter(Mandatory = $false)]
        [string] $debugLogDirectory = $DEFAULT_DEBUG_LOG_DIRECTORY
    )

    # check to ensure that the debugMode is an expected value
    # ordinarilyt, this would be caught by the parameter definition in each function (though the use of the ValidateScript attribute)
    # However, if the -debugMode parameter is not specified, the ValidateScript is not used. This means that if the user
    # set a default value for this parameter (either via the .psm1 file or a system environment value), they could have a bad/unexpected value
    if($debugMode -notin ('EVT', 'File', 'Both')){
        Write-Host "[[ DEBUG WARNING: debugMode parameter is not an expected value! We expect it to be 'EVT', 'File', or 'Both', but the value is '$debugMode'.`nThis may have happened if the default value was incorrectly set in the module's .psm1 file or the CERTIFICAT_DEFAULT_DEBUG_MODE system environment variable.`nDebug logging will NOT occur!]]" -ForegroundColor Red -BackgroundColor Black
        return
    }

    # build the message to be logged
    $logMessage = "[ CertifiCat-ps Debug Message ]`n"
    $logMessage += "Function: $callingFunction `n"
    $logMessage += "Completed: $(Get-Date)`n"

    if($null -ne $env:userdomain){
        $logMessage += "Running As User: $($env:userdomain)\$($env:USERNAME)`n"
    } else {
        $logMessage += "Running As User: $($env:USERNAME)`n"
    }
    $logMessage += "Function Return Object:`n"

    # attempt to pretty-print the function return object into something slightly more readable
    $fro | Get-Member | where-object {$_.MemberType -eq "NoteProperty"} | foreach-object {

        $propType = ($_.Definition -split "\s")[0]

        # check to see what type of property this is -- we only want to expand object arrays
        if($_.Definition -match 'Object\[\]'){
            # Some objects may just be a simple array list, while others may be an array of key-value pairs, so we need to account for both
           if($null -eq $fro.($_.Name).Keys){
                # This is a simple array list -- make sure it's not null
                if(($fro.($_.Name).Length -lt 1)){
                    $logMessage += "`t-> Property '$($_.Name)' is an object whose contents are null`n"    
                } else {
                    $logMessage += "`t-> Property '$($_.Name)' is an object and with the following contents:`n"
                    $_ | foreach-object{
                        $logMessage += "`t`t->$($fro.($_.Name))`n"
                    }
                }
            } else {
                # This is an array with key/value pairs, so let's enumerate it
                $logMessage += "`t-> Property '$($_.Name)' is an object of type '$propType' and with the following properties:`n"
                foreach($prop in $($fro.($_.Name))){
                    $logMessage += "`t`t$($prop.Keys): $($prop.Values)`n"
                }
            }
        } else {
            $logMessage += "`t-> Property '$($_.Name)' is of type '$propType' and has value: $($fro.($_.Name))`n"
        }

    }

    $logMessage += "--------------------------------------------------------------`n"

    # check to see if we're logging to a file
    if(($debugMode -eq "file") -or ($debugMode -eq "both")){
        # make sure that the directory exists
        if(-not (Test-Path $debugLogDirectory)){
            New-Item -ItemType Directory -Path $debugLogDirectory | Out-Null
        }

        $logMessage | Out-File "$debugLogDirectory\certificat-debug-$(get-date -format "MM-dd-yyyy").log" -Append
    }

    # check to see if we're logging to the event log
    if(($debugMode -eq "EVT") -or ($debugMode -eq "both")){
        # make sure we have admin access -- needed to interact with the event log
        if(!(Assert-AdminAccess -hideOutput)) {
            # we don't -- check to see if we have a log file path we can fall back to
            if(($null -ne $debugLogDirectory) -or ($debugLogDirectory -ne "")){
                Write-Host "[[ DEBUG WARNING: debugMode parameter specified logging to the Windows Event Log, however, we don't have administrative access. Debug data WILL NOT be written to the event log! ]]" -ForegroundColor Red -BackgroundColor Black
            }
        } else {
            # check to see if the event log source we want exists
            if( -not [System.Diagnostics.EventLog]::SourceExists($DEFAULT_EVENT_LOG_SOURCE)){
                # create it
                [System.Diagnostics.EventLog]::CreateEventSource($DEFAULT_EVENT_LOG_SOURCE, "Application")
            }

            # determind the log level
            if($functionSucceeded){ $logLevel = "Information" } else { $logLevel = "Error" }

            # get the event id we care about
            $eventID = Get-DebugEventID $callingFunction $functionSucceeded

            # make sure that we have an event id
            if($null -ne $eventID){
                # write the log
                [System.Diagnostics.EventLog]::WriteEntry($DEFAULT_EVENT_LOG_SOURCE, $logMessage, $logLevel, $eventId)
            } else {
                Write-Host "[[ DEBUG WARNING: debugMode parameter specified logging to the Windows Event Log, however, we couldn't find an event ID associated with function '$callingFunction' and functionSucceeded = '$functionSucceeded'. Debug data WILL NOT be written to the event log! ]]" -ForegroundColor Red -BackgroundColor Black
            }
        }
    }
}