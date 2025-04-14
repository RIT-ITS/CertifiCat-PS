function Add-PAAccount{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    param(
        [Parameter(Mandatory=$true, Position=1)]
        $paUserID,
        [Parameter(Mandatory=$true, Position=2)]
        $paUserKey
    )

    Write-Host "`t-> Adding new account on server..." -NoNewline
    $pa = New-PAAccount -ExtAcctKID $paUserID -ExtAcctHMACKey $paUserKey -AcceptTOS -WarningAction SilentlyContinue


    if($null -ne $pa.id){
        Write-Ok

        Write-Host "`tNew account with ID: '$($pa.id)' created successfully!"

        return $pa
    } else {
        Write-Fail

        Write-Host "`tFailed to create new account on this server! Please verify the external account ID and Key values and try again." -ForegroundColor Red -BackgroundColor Black

        return $null
    }
}