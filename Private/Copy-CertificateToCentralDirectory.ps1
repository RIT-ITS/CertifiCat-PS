function Copy-CertificateToCentralDirectory{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    param(
        [Parameter(Mandatory = $true)]
        $CentralDirectory,

        [Parameter (Mandatory = $true)]
        $CertCurrentDirectory
    )
    # copy the certificate to a central location, if needed
    Write-Host "-> Copying certificate from Posh-ACME working directory to central directory..."
    Write-Host "`tChecking / creating destination directory '$CentralDirectory'..." -NoNewLine

    if(Test-Path $CentralDirectory){
        Write-Ok
    } else {
        $newDir = New-Item -ItemType Directory -Path $CentralDirectory
        if($null -ne $newDir){
            Write-Ok
        } else {
            Write-Fail
            return "directory"
        }
    }

    Write-Host "`tCopying certificate files to new destination directory..." -NoNewLine

    Copy-Item "$CertCurrentDirectory\*" -exclude *.bak $CentralDirectory
    if($?) {
        Write-Ok
        return "ok"

    } else {
        Write-Fail
        return "copy"
    }
}