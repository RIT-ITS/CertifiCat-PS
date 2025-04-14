[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
param()
<#
    Sample Script: IIS - Single Server

    1. Request a new certificate from a primary server
    2. Install the certificate and update all IIS SSL bindings
    3. Build a 'log' of the results of these operations and optionally post to Slack
#>

# ################################# #
#          SCRIPT VARIABLES         #
# Modify the values below as needed #
# ################################# #

# The path and filename of the log file that we'll create as part of this script
$logFile = "$($env:ProgramData)\CertifiCat-PS\logs\operational\certificat-ps-Log-$(get-date -format "MM-dd-yyyy-hh-mm-ss").txt"

# A list of domains that should be included in the certificate. The first domain in the list will be the primary domain and the subsequent ones will be included as SANs
$DomainList = "web1.example.com","web2.example.com"

# When true, CertifiCat-PS will validate each of the domains in the list above to ensure that they are expected
# CertifiCat-PS is configured by default to validate domains against the pattern: "(.)*.rit.edu". To modify this, use Set-CertifiCatDomainValidation -domainPattern "regex pattern here"
# To disable this check completely, set this value to $false
$ValidateDomains = $true

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
        Start-Sleep -Seconds 180 # 3 Minutes

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

    # Check the host to ensure that the certificate is actually new
    $serverTest = Assert-SiteCertificate -hostToTest $MainDomain -portToTest $tlsPortToTest

    if($serverTest.CertificateThumbprint -eq $newCert.Certificate.Thumbprint){
        $serverValidated = $true
    } else {
        $serverValidated = $false
        Write-Host "Certificate does not appear to have been changed. We would expect the server to be presenting thumbprint $($newCert.Certificate.Thumbprint) but it is presenting $($serverTest.CertificateThumbprint). Did something happen with the renewal?"
    }

    if($PostToSlack -and !([string]::IsNullOrEmpty($slackUrl))){
        # Build overall status message for slack
        if(($serverValidated) -and ($newCert.CertificateImported) -and ($newCert.BindingsUpdated) -and ($newCert.CertificateCentralized)){
            $slackMain = "ACME Certificate Renewed *Successfully* on *$([System.Net.Dns]::GetHostByName($env:computername).HostName)*:\n"
        } else {
            $slackMain = "ACME Certificate Renewed *Unsuccessfully* on *$([System.Net.Dns]::GetHostByName($env:computername).HostName)*:\n"
        }

        # Build emoji for each step
        $slackMain += "Import Cert into Store: "
        if($newCert.CertificateImported) { $slackMain += ":white_check_mark:" } else { $slackMain += ":warning:"}

        $slackMain += " | Centralize Cert Material: "
        if($newCert.CertificateCentralized) { $slackMain += ":white_check_mark:" } else { $slackMain += ":warning:"}

        $slackMain += " | Update Binding(s): "
        if($newCert.BindingsUpdated) { $slackMain += ":white_check_mark:" } else { $slackMain += ":warning:"}

        $slackMain += " | Validate Server Cert: "
        if($serverValidated) { $slackMain += ":white_check_mark:" } else { $slackMain += ":warning:"}

        #construct a link to crt.sh
        $crtShLink = "https://crt.sh?serial=" + $newCert.Certificate.SerialNumber

        #obtain the SAN list
        $certSans = $newCert.Certificate.DnsNameList -join ", "

        # build the footer
        $slackFooter = "Log in: $logFile\nCertificate SANs: $certSans\nFull Certificate Details: $crtShLink"

        # Construct the payload
        $slackPayload = @{ "blocks" = @(@{ "type" = "section"; "text" = @{ "type" = "mrkdwn"; "text" = $slackMain } }; @{ "type" = "context"; "elements" = @( @{ "type" = "mrkdwn";	"text" = $slackFooter }	)};)}

        # Post to Slack
        Invoke-RestMethod -Uri $slackUrl -Method Post -Body (ConvertTo-Json $slackPayload -depth 5).Replace('\\n', '\n')
    }

} else {
    # Nothing to do here -- we'll log that the certificate isn't ready for renewal yet
    Write-Host "Not ready to renew! Certificate expires: $(($readyToRenew.Certificates)[0].NotAfter)"
}

# log the end time
$endTime = Get-Date

# Add a few remaining bits and close the log
Write-Host "Script Started: $startTime  |  Ended: $endTime  |  Total Execution Time: $($endTime - $startTime)"
if($readyToRenew.ReadyForRenewal) { Write-Host "Total Retires Needed to Retrieve Cert: $totalRetries" }

Stop-Transcript