function Edit-ACMEProxyRedirect{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PsUseUsingScopeModifierInNewRunspaces', '', Justification = 'TODO via issue #25: https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/25')]
    param(
        $TargetServer,
        $URLRewriteRuleName,
        $EnableRule,
        $iisSiteName
    )

    # calculate a simpler boolean to control whether we're running things locally or remotely
    if(($null -eq $TargetServer) -or ($TargetServer -eq "")){ $isLocal = $true } else { $isLocal = $false }

    # generate a function return object to keep track of what was done
    $fro = [PSCustomObject]@{
        WebAdministrationModuleLoaded = $true;
        RuleFound = $true;
        RuleToggledSuccessfully = $true;
        RemoteConnectionOK = $true;
        Errors = '';
    }

    # if we are running on a remote server, make sure that we can actually connect
    # (e.g. verifying the host is valid, that we have access, and that there isn't a Kerberos double-hop issue)
    if(!$isLocal){
        Write-Host "-> Verifying connectivity to remote server '$TargetServer'..." -NoNewline

        $rmSession = New-PSSession $TargetServer -ErrorAction SilentlyContinue -ErrorVariable psError

        if($null -eq $rmSession){
            # something happened -- we can't make the remote connection -- cannot continue!
            Write-Fail
            $fro.RuleFound = $false
            $fro.RuleToggledSuccessfully = $false
            $fro.WebAdministrationModuleLoaded = $false
            $fro.RemoteConnectionOK = $false
            $fro.Errors += $psError

            Write-Host "`tFailed to connect to target server '$TargetServer' -- check to ensure the account running PowerShell, and that you aren't already in a remote session. Error is: $psError" -ForegroundColor Red
            return $fro
        } else {
            Write-Ok
        }
    }

    # check to ensure that we have the web administration module we need to access the function
    Write-Host "-> Ensuring that we have the WebAdministration module available..." -NoNewline

    if($isLocal){
        $hasFunction = Get-Command Get-WebConfigurationProperty -ErrorAction SilentlyContinue
    } else {
        $hasFunction = Invoke-Command -ComputerName $TargetServer -ScriptBlock { Get-Command Get-WebConfigurationProperty -ErrorAction SilentlyContinue }
    }

    if($null -eq $hasFunction){
        Write-Fail
        $fro.RuleFound = $false
        $fro.RuleToggledSuccessfully = $false
        $fro.WebAdministrationModuleLoaded = $false
        return $fro
    } else {
        Write-Host "ok" -ForegroundColor Green
    }

    # obtain the existing rewrite rule
	Write-Host "-> Querying for URL Rewrite rule for ACME proxy redirect..." -NoNewline
    if($isLocal){
        $existingRule = Get-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known" -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']" -name "."
    } else {
        $existingRule = Invoke-Command -ComputerName $TargetServer -ScriptBlock { param($iisSiteName, $URLRewriteRuleName) Get-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($Using:iisSiteName)/.well-known" -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']" -name "." } -ArgumentList  $iisSiteName, $URLRewriteRuleName
    }


    if($null -eq $existingRule){
        Write-Host "fail!" -ForegroundColor Red
        $fro.RuleFound = $false
        $fro.RuleToggledSuccessfully = $false
        return $fro
    } else {
        Write-Host "ok" -ForegroundColor Green
    }


    if($EnableRule){
        if($isLocal){
            Write-Host "-> Enabling rule '$URLRewriteRuleName' in site '$iisSiteName' on current server..." -NoNewline
            Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known"  -filter "system.webServer/rewrite/rules/rule[@name='$URLRewriteRuleName']" -name "enabled" -value "True"

            if((get-webconfigurationproperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known" -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']" -name "Enabled").Value -eq $true){
                Write-Host "ok" -ForegroundColor Green
            } else {
                Write-Host "fail!" -ForegroundColor Red
                $fro.RuleToggledSuccessfully = $false
            }
        } else {
            Write-Host "-> Enabling rule '$URLRewriteRuleName' in site '$iisSiteName' on '$TargetServer'..." -NoNewline
            Invoke-Command -ComputerName $TargetServer -ScriptBlock { param($iisSiteName, $URLRewriteRuleName) Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known"  -filter "system.webServer/rewrite/rules/rule[@name='$URLRewriteRuleName']" -name "enabled" -value "True" } -ArgumentList  $iisSiteName, $URLRewriteRuleName

            if((Invoke-Command -ComputerName $TargetServer -ScriptBlock { param($iisSiteName, $URLRewriteRuleName) get-webconfigurationproperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known" -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']" -name "Enabled"} -ArgumentList  $iisSiteName, $URLRewriteRuleName ).Value -eq $true){
                Write-Host "ok" -ForegroundColor Green
            } else {
                Write-Host "fail!" -ForegroundColor Red
                $fro.RuleToggledSuccessfully = $false
            }
        }
    } else {
        if($isLocal){
            Write-Host "-> Disabling rule '$URLRewriteRuleName' in site '$iisSiteName' on current server..." -NoNewline
            Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known"  -filter "system.webServer/rewrite/rules/rule[@name='$URLRewriteRuleName']" -name "enabled" -value "False"

            if((get-webconfigurationproperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known" -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']" -name "Enabled").Value -eq $false){
                Write-Host "ok" -ForegroundColor Green
            } else {
                Write-Host "fail!" -ForegroundColor Red
                $fro.RuleToggledSuccessfully = $false
            }
        } else {
            Write-Host "-> Disabling rule '$URLRewriteRuleName' in site '$iisSiteName' on '$TargetServer'..." -NoNewLine
            Invoke-Command -ComputerName $TargetServer -ScriptBlock { param($iisSiteName, $URLRewriteRuleName) Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known"  -filter "system.webServer/rewrite/rules/rule[@name='$URLRewriteRuleName']" -name "enabled" -value "False" } -ArgumentList  $iisSiteName, $URLRewriteRuleName

            if((Invoke-Command -ComputerName $TargetServer -ScriptBlock { param($iisSiteName, $URLRewriteRuleName) get-webconfigurationproperty -pspath "MACHINE/WEBROOT/APPHOST/$($iisSiteName)/.well-known" -filter "system.webServer/rewrite/rules/rule[@Name='$URLRewriteRuleName']" -name "Enabled"} -ArgumentList  $iisSiteName, $URLRewriteRuleName ).Value -eq $false){
                Write-Host "ok" -ForegroundColor Green
            } else {
                Write-Host "fail!" -ForegroundColor Red
                $fro.RuleToggledSuccessfully = $false
            }
        }
    }

    return $fro
}