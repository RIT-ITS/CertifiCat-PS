[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '', Justification = 'TODO via issue #26: https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/26')]
param()
<#
    Sample Script: IIS - Multiple Servers

    1. Request a new certificate from a primary server
    2. Install the certificate and update all IIS SSL bindings
    3. Copy the new certificate to the remaining servers
    4. Import the certificate and update bindings on the remaining servers
    5. Build a 'log' of the results of these operations and optionally post to Slack

    Note: This specific script is intended to facilitate the installation of a single certificate, containing multiple SANs, across a pool of servers.
    Be sure that you have configured your environment to redirect ACME challenge requests from all other pool members to the node that will be running this script.
    For more information, see the wiki -- you can also use Initialize-ACMERedirect to configure a redirect for ACME challenge requests on the other nodes in the pool.
#>

# ################################# #
#          SCRIPT VARIABLES         #
# Modify the values below as needed #
# ################################# #

# The path and filename of the log file that we'll create as part of this script
$logFile = "$($env:ProgramData)\CertifiCat-PS\logs\operational\certificat-ps-Log-$(get-date -format "MM-dd-yyyy-hh-mm-ss").txt"

# A list of domains that should be included in the certificate. The first domain in the list will be the primary domain and the subsequent ones will be included as SANs
$DomainList = "web1.example.com", "web2.example.com", "web3.example.com", "web.example.com"

# When true, CertifiCat-PS will validate each of the domains in the list above to ensure that they are expected
# CertifiCat-PS is configured by default to validate domains against the pattern: "(.)*.rit.edu". To modify this, use Set-CertifiCatDomainValidation -domainPattern "regex pattern here"
# To disable this check completely, set this value to $false
$ValidateDomains = $true

# Provide a list of secondary servers to which the new certificate will be copied
$secondaryServers = "web2.example.com", "web3.rit.edu"

# Set to true to use the Assert-SiteCertificate function on all secondary servers as part of verifying whether this script ran successfully or not
# When false, the function will only be run on the main domain (i.e. the first domain the list)
$assertAllServers = $true

# Set to true to post a message to Slack upon script completion
$PostToSlack = $true

# Provide the Slack incoming webhook URL to use, if desired
$slackUrl = ""

# Provide the port that should be tested at the end of the script as part of validating the certificate installation
$tlsPortToTest = 443

# Specify the maximum number of attempts that the script should make to obtain a certificate
# This is useful in cases where the ACME server (or upstream certificate provider) is slow in processing the request
$maxRetries = 8

# This specifies the maximum possible number of seconds that the script will randomly wait before requesting a new certificate
# This is useful when multiple servers are scheduled for simultaneous renewal
# To disable this, set the value to 0
$maxJitter = 1800

# ################################# #
#            BEGIN SCRIPT           #
# ################################# #

# log the start time
$startTime = Get-Date

# Build a log file (for simplicity, we'll just use Powershell's build-in Start-Transcript)
Start-Transcript $logFile

# Import the CertifiCat-PS module
Import-Module CertifiCat-PS -Force

if($null -eq (Get-Module CertifiCat-PS)){
    return "Unable to load the CertifiCat-PS module -- please verify that it is installed (was it possibly installed in the scope of a CurrentUser rather than LocalMachine?)"
}

# Extract the primary domain from the DomainList
if($DomainList.Count -gt 1){
    $MainDomain = $DomainList[0]
} else {
    $MainDomain = $DomainList
}

# Check to see if we're ready for renewal
$readyToRenew = Confirm-ACMERenewalReadiness -DomainName $MainDomain

# Dump the contents of the return object for logging
Write-Host "`n`nConfirm-ACMERenewalReadiness Object:"
$readyToRenew

# Check to see if we're really ready to renew
if($readyToRenew.ReadyForRenewal){
    # We are -- let's do it!
    Write-Host "Ready to renew!"

    # Call the CertifiCat-PS function to get a new cert and update our bindings
    # Decide if we should sanity check the domains in the SAN list or not
    if($ValidateDomains){
        $newCert = Initialize-NewACMECertificate -DomainList $DomainList -UpdateBindings -jitter $maxJitter
    } else {
        $newCert = Initialize-NewACMECertificate -DomainList $DomainList -UpdateBindings -jitter $maxJitter -SkipDomainValidation
    }

    # Dump the contents of the return object for logging
    Write-Host "`n`nInitialize-NewACMECertificate Object:"
    $newCert

    # count of the total number of retries needed
    $totalRetries = 0

    # Check to see if the call was successfull
    if($null -eq $newCert.Certificate.Thumbprint){
        # the ACME server (or upstream certificate issuer) might be slow in processing our request

		Write-Host "Sleeping for 3 Minutes..."
        Start-Sleep -Seconds 180

        # Attempt to repair / complete the order
        $newCert = Repair-NewACMEOrder -MainDomain $MainDomain -UpdateBindings
        $totalRetires++

        # Check to see if waiting 3 minutes was long enough
        if($null -eq $newCert.Certificate.Thumbprint){
            # It wasn't... now we're going to loop for a while and wait progressively longer
            for($attempt = 1; $attempt -le $maxRetries; $attempt++){
				# increment the retry counter
				$totalRetires++

				# calculate the amount of time to wait before retrying
				$sleepDuration = $attempt * 5 * 60 # each attempt will wait for 5 minutes * the attempt number (converted to seconds for start-sleep)
				Write-Host "Sleeping for $($sleepDuration / 60) Minutes..."
                Start-Sleep $sleepDuration

                # Attempt another repair
                $newCert = Repair-NewACMEOrder -MainDomain $MainDomain -UpdateBindings

				# Dump the contents of the return object for logging
				Write-Host "`n`nRepair-NewACMEOrder Object after $attempt additional attempt(s):"
				$newCert

                # Check to see if we now have the certificate
                if($null -ne $newCert.Certificate.Thumbprint){
					# we have the certificate -- we can exit out of the loop
                    $attempt = 1000
                }
            }
        } else {
			# We retrieved the cert after one retry
			# Dump the contents of the return object for logging
			Write-Host "`n`nRepair-NewACMEOrder Object after initial attempt:"
			$newCert
		}
    }

	# Check to ensure that we have a valid cert to update on the secondary servers
	if($null -ne $newCert.PFXPath){
		# Get the PFX file from the primary server
		$newPFXFile = $newCert.PFXPath

		# Extract just the directory name and convert it to a remote UNC-compatible (e.g. c:\ -> c$\)
		$newPFXDirectory = ($newPFXFile.replace(":", "$")).replace("cert.pfx", "")

		# Variables for secondary server updates
		$secondaryOk = $true
		$secondaryDetails = ""

		# Loop the list of servers, create the destination directory, copy the PFX file, and then run our function to import the file and perform the downstream functions
		foreach($server in $SecondaryServers){
			If(!(Test-Path \\$server\$newPFXDirectory)) { New-Item -ItemType Directory -Path "\\$server\$newPFXDirectory" | out-null }

			Copy-Item $newPFXFile "\\$server\$newPFXDirectory\cert.pfx" -Force

			$update = Invoke-Command -ComputerName $server -ScriptBlock { param($newPFXFile) Import-Module CertifiCat-PS -Force;  Initialize-ExistingACMECertificate -PfxPath $newPFXFile -UpdateBindings } -ArgumentList $newPFXFile

			$secondaryDetails += "-> $server = Certificate Imported: "
			if($update.CertificateImported){
				$secondaryDetails += ":white_check_mark:"
			} else {
				$secondaryDetails += ":warning:"
				$secondaryOk = $false
			}

			$secondaryDetails += " | Binding Updated: "
			if($update.BindingsUpdated){
				$secondaryDetails += ":white_check_mark:"
			} else {
				$secondaryDetails += ":warning:"
				$secondaryOk = $false
			}

			$secondaryDetails += "\n"

			"[[Update Details for $server]]"
			$update | Out-Host
		}
	}

    # Check the host to ensure that the certificate is actually new
    if($assertAllServers){
        $certsValidated = $true

        foreach($serverToTest in $domainList){
            $serverTest = Assert-SiteCertificate -hostToTest $serverToTest -portToTest $tlsPortToTest

            if($serverTest.CertificateThumbprint -ne $newCert.Certificate.Thumbprint){
                $certsValidated = $false
                Write-Host "Certificate does not appear to have been changed on '$server'. We would expect the server to be presenting thumbprint $($newCert.Certificate.Thumbprint) but it is presenting $($serverTest.CertificateThumbprint). Did something happen with the renewal?"
            }
        }
    } else {
        $serverTest = Assert-SiteCertificate -hostToTest $MainDomain -portToTest $tlsPortToTest

        if($serverTest.CertificateThumbprint -eq $newCert.Certificate.Thumbprint){
            $certsValidated = $true
        } else {
            $certsValidated = $false
            Write-Host "Certificate does not appear to have been changed. We would expect the server to be presenting thumbprint $($newCert.Certificate.Thumbprint) but it is presenting $($serverTest.CertificateThumbprint). Did something happen with the renewal?"
        }
    }

    if($PostToSlack -and !([string]::IsNullOrEmpty($slackUrl))){
        # Build overall status message for slack
        if(($secondaryOk) -and $certsValidated -and ($newCert.CertificateImported) -and ($newCert.BindingsUpdated) -and ($newCert.CertificateCentralized)){
            $slackMain = "ACME Farm Certificate Renewed *Successfully* from *$($env:computername)*:\n"
        } else {
            $slackMain = "ACME Farm Certificate Renewed *Unsuccessfully* from *$($env:computername)*:\n"
        }

        # Build emoji for each step
        $slackMain += "Import Cert into Store on Main Server: "
        if($newCert.CertificateImported) { $slackMain += ":white_check_mark:" } else { $slackMain += ":warning:"}

        $slackMain += "\nCentralize Cert Material on Main Server: "
        if($newCert.CertificateCentralized) { $slackMain += ":white_check_mark:" } else { $slackMain += ":warning:"}

        $slackMain += "\nUpdate Binding(s) on Main Server: "
        if($newCert.BindingsUpdated) { $slackMain += ":white_check_mark:" } else { $slackMain += ":warning:"}

        $slackMain += "\nCopy Cert to Secondary Servers and Update IIS: "
        if($secondaryOk) { $slackMain += ":white_check_mark:" } else { $slackMain += ":warning:"}

        $slackMain += "\nValidate Cert on All Servers:"
        if($certsValidated) { $slackMain += ":white_check_mark:" } else { $slackMain += ":warning:"}

        #construct a link to crt.sh
        $crtShLink = "https://crt.sh?serial=" + $newCert.Certificate.SerialNumber

        #obtain the SAN list
        $certSans = $newCert.Certificate.DnsNameList -join ", "

        # build the footer
        $slackFooter = "Log in: $logFile\nCertificate SANs: $certSans\nFull Certificate Details: $crtShLink"

        # Construct the payload
        $slackPayload = @{ "blocks" = @(@{ "type" = "section"; "text" = @{ "type" = "mrkdwn"; "text" = $slackMain } }; @{ "type" = "context"; "elements" = @( @{ "type" = "mrkdwn";	"text" = "Secondary server updates:\n$secondaryDetails" }	)}; @{ "type" = "context"; "elements" = @( @{ "type" = "mrkdwn";	"text" = $slackFooter }	)};)}

        # Post to Slack
        Invoke-RestMethod -Uri $slackUrl -Method Post -Body (ConvertTo-Json $slackPayload -depth 5).Replace('\\n', '\n')
    }

} else {
    # Nothing to do here -- we'll log that the certificate isn't ready for renewal yet
    Write-Host "Not ready to renew! Certificate expires: $(($readyToRenew.Certificates)[0].NotAfter)"
}

# log the end time
$endTime = Get-Date

# Log a few remaining bits and close the log
Write-Host "Script Started: $startTime  |  Ended: $endTime  |  Total Execution Time: $($endTime - $startTime)"
if($readyToRenew.ReadyForRenewal) { Write-Host "Total Retires Needed to Retrieve Cert: $totalRetries" }

Stop-Transcript