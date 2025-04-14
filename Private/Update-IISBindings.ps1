function Update-IISBindings{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Intentionally leaving this plural, as the function supports the ability to update -all- HTTPS bindings')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Not concerned with confirmation here, as this is a private function that is called intentionally by an upstream public function')]
    param(
        [string[]] $BindingPorts,
        [string] $StoreName
    )

    $bindingList = @()
    if($null -eq  $BindingPorts){
        Write-Host "`t-BindingPorts not specified -- looking for all HTTPS bindings..."

        Get-WebBinding -Protocol Https | ForEach-Object {
            # get the port and site name for display purposes
            $bindingPort = (($_.bindingInformation -split ":")[1])
            $siteName = ((($_.ItemXPath) -split "=")[1] -split "and")[0].replace("'", "").trim()

            #contruct an object that we'll add to the list to return
            $bindingResult = [PSCustomObject]@{
                Port = $bindingPort;
                OldThumbprint = $_.CertificateHash;
                UpdatedSuccessfully = $true;
                Binding = $null;
            }

            Write-Host "`t`tFound binding for port '$bindingPort' associated with site '$siteName' -- updating..." -NoNewline

            # Update the certificate
            $_.AddSslCertificate($importedCert.Thumbprint, $StoreName)

            # Re-obtain the binding so that we can confirm the cert change worked
            $binding = Get-WebBinding -Protocol Https -Port $BindingPort
            $bindingResult.Binding = $binding

            if($binding.certificateHash -eq $importedCert.Thumbprint){
                Write-Ok
            } else {
                Write-Fail
                Write-Host "`t`t`t`tBinding failed to update: Expected to set thumbprint '$($importedCert.Thumbprint)' but binding is still using '$($binding.certificateHash)'"
                $bindingResult.UpdatedSuccessfully = $false
            }
            $bindingList += $bindingResult
        }
    }
    else {
        Write-Host "`t-BindingPorts specified -- only looking for bindings on ports: $($BindingPorts -join ",")..."
        foreach($BindingPort in $BindingPorts){
            $binding = Get-WebBinding -Protocol Https -Port $BindingPort

            #contruct an object that we'll add to the list to return
            $bindingResult = [PSCustomObject]@{
                Port = $bindingPort;
                OldThumbprint = $binding.CertificateHash;
                UpdatedSuccessfully = $true;
                Binding = $null;
            }

            Write-Host "`t`tLooking for binding associated with port $BindingPort..." -NoNewline
            if($null -eq $binding){
                Write-Skipped
                "`t`t`tNo binding found associated with this port"
            } else {
                $siteName = ((($binding.ItemXPath) -split "=")[1] -split "and")[0].replace("'", "").trim()
                Write-Ok
                Write-Host "`t`t`tFound binding associated with site '$siteName' -- updating..." -NoNewLine

                # Update the certificate
                $binding.AddSslCertificate($importedCert.Thumbprint, $StoreName)

                # Re-obtain the binding so that we can confirm the cert change worked
                $binding = Get-WebBinding -Protocol Https -Port $BindingPort
                $bindingResult.Binding = $binding

                if($binding.certificateHash -eq $importedCert.Thumbprint){
                    Write-Ok
                } else {
                    Write-Fail
                    Write-Host "`t`t`t`tBinding failed to update: Expected to set thumbprint '$($importedCert.Thumbprint)' but binding is still using '$($binding.certificateHash)'"
                    $bindingResult.UpdatedSuccessfully = $false
                }
            }

            $bindingList += $bindingResult
        }
    }

    return $bindingList
}