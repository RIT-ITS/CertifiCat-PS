function Initialize-ACMEProxyRedirect {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [CmdletBinding()]
    param(
        [Parameter (Mandatory = $true,
            HelpMessage = "The hostname of the primary node, to which ACME challenges will redirect"
        )]
        $PrimaryServer,

        [Parameter (Mandatory = $false,
            HelpMessage = "The name of the IIS website in which the ACME redirect will be created"
        )]
        $IISSiteName = $DEFAULT_IIS_WEBSITE,

        [Parameter (Mandatory = $false,
            HelpMessage = "The name of the URL Rewrite rule that will be created to proxy ACME challenges"
        )]
        $URLRewriteRuleName = $DEFAULT_URL_REWRITE_RULE_NAME,

        [Parameter (Mandatory = $false,
            HelpMessage = "URL Rewrite Module Installer Log file"
        )]
        $URLRewriteInstallerLog = $DEFAULT_URL_REWRITE_INSTALLER_LOG,

        [Parameter (Mandatory = $false,
            HelpMessage = "URL Rewrite Module installer"
        )]
        $URLRewriteInstaller = $DEFAULT_URL_REWRITE_INSTALLER_MSI,

        [Parameter (Mandatory = $false,
            HelpMessage = "URL Rewrite Module installer download URL"
        )]
        $URLRewriteDownloadURL = $DEFAULT_URL_REWRITE_INSTALLER_DOWNLOAD_URL,

        [Parameter (Mandatory = $false,
            HelpMessage = "URL Rewrite Module installer SHA-256 hash"
        )]
        $URLRewriteInstallerExpectedHash = $DEFAULT_URL_REWRITE_INSTALLER_EXPECTED_HASH,

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
        URLRewriteDownloadURL = $URLRewriteDownloadURL;
        URLRewriteExpectedHash = $URLRewriteInstallerExpectedHash;
        URLRewriteRuleName = $URLRewriteRuleName;
        URLRewriteInstallerLocation = $URLRewriteInstaller;
        URLRewriteInstallerLog = "";
        IISSiteName = $IISSiteName;
        ProxyRedirectConfiguredSuccessfully = $true;
        debugEnabled= $debugEnabled;
        debugLogDirectory = $debugLogDirectory;
        debugMode = $debugMode;
    }

    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Configuring ACME Proxy Redirect"

    if(!(Assert-AdminAccess)) {
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "Session lacks administrative access. Ensure that PowerShell was run as an Administrator."
        $fro.FunctionSuccess = $false
        $fro.ProxyRedirectConfiguredSuccessfully = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
    }

    # Check to ensure that we aren't running from a PowerShell 7 console
    Write-Host "-> Checking to ensure that we are running in a PowerShell 6 or earlier console..." -NoNewLine
    if(!(Assert-PSVersion)){
        Write-Fail

        Write-Host "`tDetected this function running from a modern PowerShell console. This function requests the use of PowerShell 6 or older. Check the 'PS5Command' property of the return object for a complete command to run instead." -ForegroundColor Red
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "Function requires PowerShell 6 or earlier, but running from a modern console. See the PS5Command property for a PowerShell 5 equivalent to run."
        $fro.FunctionSuccess = $false
        $fro.ProxyRedirectConfiguredSuccessfully = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
    } else {
        Write-Ok
    }

    Write-Host "-> Confirming that IIS is installed..." -NoNewline
    if((get-windowsfeature web-server).InstallState -ne "Installed"){
        Write-Fail

        Write-Host "`tIIS does not appear to be installed. This function is only for use when IIS is installed and used!" -ForegroundColor Red
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "IIS role not detected -- it can be setup minimally using 'Install-WindowsFeature web-server'"
        $fro.FunctionSuccess = $false
        $fro.ProxyRedirectConfiguredSuccessfully = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
    } else {
        Write-Ok
    }

    Write-Host "-> Confirming URL Rewrite Module installation..." -NoNewline
    if(Test-Path "$($env:systemroot)\system32\inetsrv\rewrite.dll"){
        Write-Ok
    } else {
        Write-Pending

        Write-Host "`tChecking for existing IIS URL Rewrite Module installer in $URLRewriteInstaller..." -NoNewline
        if(Test-Path $URLRewriteInstaller){
            Write-Ok
        } else {
            Write-Pending
            Write-Host "`tDownloading IIS URL Rewrite Module..." -NoNewLine
            $fro.URLRewriteDownloadURL = $URLRewriteDownloadURL

            Invoke-WebRequest $URLRewriteDownloadURL -OutFile $URLRewriteInstaller -ErrorAction SilentlyContinue

            if(Test-Path $URLRewriteInstaller){
                Write-Ok
            } else {
                Write-Fail

                Write-Host "`tFailed to download the URL Rewrite Module!" -ForegroundColor Red
                Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

                $fro.Errors += "URL Rewrite module not found on server, and download from Microsoft failed! See the URLRewriteDownloadURL property for the URL that was used to download."
                $fro.FunctionSuccess = $false
                $fro.ProxyRedirectConfiguredSuccessfully = $false

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                }

                return $fro
            }
        }

        Write-Host "`tVerifying hash of URL Rewrite Installer (for security purposes)..." -NoNewline
        $URLRewriteInstallerDLHash = (Get-FileHash $URLRewriteInstaller -Algorithm SHA256).Hash
        if($URLRewriteInstallerDLHash -eq $URLRewriteInstallerExpectedHash){
            Write-Ok
        } else {
            Write-Fail

            Write-Host "`t`tURL Rewrite module installer hash did not match what we expect!" -ForegroundColor Red
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            $fro.Errors += "URL Rewrite module installer hash ($URLRewriteInstallerDLHash) does not match the expected hash ($URLRewriteInstallerExpectedHash)"
            $fro.FunctionSuccess = $false
            $fro.ProxyRedirectConfiguredSuccessfully = $false

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

            return $fro
        }

        Write-Host "`tUnblocking installer..." -NoNewline
        Unblock-File $URLRewriteInstaller
        if($?) {
            Write-Ok
        } else {
            Write-Fail

            Write-Host "`t`tURL Rewrite module installer failed to unblock!" -ForegroundColor Red
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            $fro.Errors += "URL Rewrite module installer failed to unblock!"
            $fro.FunctionSuccess = $false
            $fro.ProxyRedirectConfiguredSuccessfully = $false

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

            return $fro
        }

        Write-Host "`tInstalling URL Rewrite Module..." -NoNewline
        $i = start-process msiexec -ArgumentList @('/i', "`"$URLRewriteInstaller`"", "/q", "/norestart", "/l*v $URLRewriteInstallerLog") -PassThru -Wait
        $fro.URLRewriteInstallerLog = $URLRewriteInstallerLog;

        if($i.ExitCode -eq 0){
            Write-Ok
        } else {
            Write-Fail

            Write-Host "`t`tURL Rewrite module failed to install (installer exit code = $($i.ExitCode)!" -ForegroundColor Red
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            $fro.Errors += "URL Rewrite module installer failed with exit code $($i.ExitCode) -- please review logs as indicated by the URLRewriteInstaller parameter."
            $fro.FunctionSuccess = $false
            $fro.ProxyRedirectConfiguredSuccessfully = $false

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

            return $fro
        }
    }

    Write-Host "-> Obtaining Web Site ($iisSiteName)..." -NoNewline
    $iisSite = Get-WebSite $IISSiteName

    if($null -eq $iisSite){
        Write-Fail

        Write-Host "`tUnable to find IIS Site with name '$IISSiteName'" -ForegroundColor Red
        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        $fro.Errors += "Unable to find IIS Site with name '$IISSiteName'"
        $fro.FunctionSuccess = $false
        $fro.ProxyRedirectConfiguredSuccessfully = $false

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
    } else {
        Write-Ok
    }

    Write-Host "-> Checking for an existing Application or Virtual Directory called '.well-known'..." -NoNewline
    if((($null -eq (Get-WebApplication .well-known)) -and ($null -eq (Get-WebVirtualDirectory .well-known)))){
        Write-Pending

        $wkPath = $iisSite.physicalpath
        $wkPath = $wkPath.replace("%SystemDrive%", $env:systemdrive) + "\.well-known"

        Write-Host "`tChecking for .well-known directory in IIS Site root ($wkPath)..." -NoNewLine
        if(Test-Path $wkPath){
            Write-Ok
        } else {
            Write-Pending
            Write-Host "`t`tCreating .well-known directory in IIS Site root ($wkPath)..." -NoNewLine

            $wkDir = New-Item -ItemType Directory -Path $wkPath -ErrorAction SilentlyContinue
            if($null -ne $wkDir){
                Write-Ok
            } else {
                Write-Fail

                Write-Host "`t`t`tFailed to create .well-known directory as '$wkDir'" -ForegroundColor Red
                Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

                $fro.Errors += "Failed to create .well-known directory as '$wkDir'"
                $fro.FunctionSuccess = $false
                $fro.ProxyRedirectConfiguredSuccessfully = $false

                # write debug information if desired
                if($debugEnabled){
                    Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
                }

                return $fro
            }
        }

        Write-Host "`tCreating new Virtual Directory '.well-known'..." -NoNewline
        $wkVD = New-WebVirtualDirectory -Site $iisSite.Name -Name .well-known -PhysicalPath $wkPath
        if($null -ne $wkVD){
            Write-Ok
        } else {
            Write-Fail

            Write-Host "`t`tFailed to create new .well-known virtual directory in Site '$IISSiteName'" -ForegroundColor Red
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            $fro.Errors += "Failed to create new .well-known virtual directory in Site '$IISSiteName'"
            $fro.FunctionSuccess = $false
            $fro.ProxyRedirectConfiguredSuccessfully = $false

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

            return $fro
        }
    } else {
        Write-Ok
    }

    Write-Host "-> Checking for URL Rewrite Rule '$URLRewriteRuleName'..." -NoNewline
    $existingRule = Get-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known" -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']" -name "."
    if($null -ne $existingRule){
        Write-Ok
    } else {
        Write-Pending

        Write-Host "`tCreating new rule (this will take a moment)..." -NoNewline

        Add-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$iisSiteName/.well-known"  -filter "system.webServer/rewrite/rules" -name "." -value @{name=$URLRewriteRuleName;stopProcessing='True'}
        Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$iisSiteName/.well-known"  -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']/match" -name "url" -value "acme-challenge/.*"
        Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$iisSiteName/.well-known"  -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']/action" -name "type" -value "Redirect"
        Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$iisSiteName/.well-known"  -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']/action" -name "url" -value "http://$PrimaryServer/.well-known/{R:0}"
        Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$iisSiteName/.well-known"  -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']/action" -name "redirectType" -value "Found"

        $rwrMatchUrl = (Get-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known" -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']/match" -name "url").Value
        $rwrActionType = (Get-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known" -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']/action" -name "type")
        $rwrActionURL  = (Get-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known" -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']/action" -name "url").Value
        $rwrActionRedirectType = (Get-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known" -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']/action" -name "redirectType")

    if(($rwrMatchUrl -ne "acme-challenge/.*") -or ($rwrActionType -ne "Redirect") -or ($rwrActionURL -ne "http://$PrimaryServer/.well-known/{R:0}") -or ($rwrACtionRedirectType -ne "Found")){
            Write-Fail

            Write-Host "`t`tFailed to create and/or fully configure the '$URLRewriteRuleName' URL Rewrite Rule" -ForegroundColor Red
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            $fro.Errors += "Failed to create and/or fully configure the '$URLRewriteRuleName' URL Rewrite Rule. Expected match URL = '.*' (set '$rwrMatchUrl') | Expected action type = 'Redirect' (set '$rwrActionType') | Expected action url = 'http://$PrimaryServer/.well-known/{R:0}' (set '$rwrActionUrl') | Expected action redirectType = 'Found' (set '$rwrActionRedirectType')"
            $fro.FunctionSuccess = $false
            $fro.ProxyRedirectConfiguredSuccessfully = $false

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

            return $fro
        } else {
            Write-Ok
        }
    }

    Write-Host "-> Checking SSL Settings = None / SSL Disabled..." -NoNewline
    $sslFlags = (Get-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known" -filter "system.webServer/security/access" -name "sslFlags").Value
    if($sslFlags -eq 0){
        Write-Ok
    } else {
        Write-Pending
        Write-Host "`tDisabling 'Require SSL' setting..." -NoNewLine
        Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -location "$iisSiteName/.well-known" -filter "system.webServer/security/access" -name "sslFlags" -value "None"

        $sslFlags = (Get-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known" -filter "system.webServer/security/access" -name "sslFlags").Value
        if($sslFlags -eq 0){
            Write-Ok
        } else {
            Write-Fail

            Write-Host "`t`tFailed to disable 'Require SSL' setting" -ForegroundColor Red
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            $fro.Errors += "Failed to disable 'Require SSL' setting"
            $fro.FunctionSuccess = $false
            $fro.ProxyRedirectConfiguredSuccessfully = $false

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

            return $fro
        }
    }
    Write-Host "-> Checking for HTTP Binding on Port 80..." -NoNewline
    if($null -ne (Get-WebBinding -Port 80)){
        Write-Ok
    } else {
        Write-Pending

        Write-Host "`tCreating new HTTP Binding on port 80..." -NoNewline
        New-WebBinding -Name $iisSiteName -IPAddress '*' -Port 80

        if($null -ne (Get-WebBinding -Port 80)){
            Write-Ok
        } else {
            Write-Fail

            Write-Host "`t`tFailed to create HTTP binding on port 80 for Site '$IISSiteName'" -ForegroundColor Red
            Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

            $fro.Errors += "Failed to create HTTP binding on port 80 for Site '$IISSiteName'"
            $fro.FunctionSuccess = $false
            $fro.ProxyRedirectConfiguredSuccessfully = $false

            # write debug information if desired
            if($debugEnabled){
                Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
            }

            return $fro
        }
    }

    Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"

    # write debug information if desired
    if($debugEnabled){
        Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
    }

    return $fro
}