function Assert-PSVersion{
    if($PSVersionTable.PSVersion.Major -gt 6){
        return $false
    } else {
        return $true
    }
}