function Assert-PSACME{
    if($null -ne (Get-Module -ListAvailable -Name Posh-ACME)){
        return $true
    } else {
        return $false
    }
}