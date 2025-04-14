
function Assert-SiteCertificate{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [CmdletBinding()]
    param(
        [Parameter (Mandatory = $true,
            HelpMessage = "The hostname to test -- this should not include any http(s) at the beginning of the hostname"
        )]
        $hostToTest,

        [Parameter (Mandatory = $true,
            HelpMessage = "The port number on which to test"
        )]
        $portToTest,

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
        [string] $debugMode = $DEFAULT_DEBUG_MODE,

        [Parameter(Mandatory = $false,
            DontShow = $true
        )]
        [switch]$mrao
    )

    # check to see if the global debug environment variable is set
    if($null -ne $env:CERTIFICAT_DEBUG_ALWAYS){
        $debugEnabled = $true
    }

    # check for any trailing https:// at the beginning of the hostname and remove it, just in case
    $hostToTest = $hostToTest.replace("https://", "")

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
       Certificate = $null;
       CertificateIssueDate = '';
       CertificateExpirationDate = '';
       CertificateThumbprint = '';
       CertificateSerialNumber = '';
       CertificatePublicKeyType = '';
       CertificatePublicKeyBits = '';
       HostTested = $hostToTest;
       PortTested = $portToTest;
       debugEnabled= $debugEnabled;
       debugLogDirectory = $debugLogDirectory;
       debugMode = $debugMode;
   }

   Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Checking Site Certificate"

   Write-Host "-> Attempting to make an SSL connection to '$hostToTest' on port $portToTest..." -NoNewLine

   # See this post -- note that the typical way to do this with ServicePointManager ONLY works in PS 5 or older (.NET Framework)
   # Testing via an SSL Connection/TCP connection works in BOTH versions, so we'll just use that...
   # https://stackoverflow.com/questions/22233702/how-to-download-the-ssl-certificate-from-a-website-using-powershell
   # https://learn.microsoft.com/en-us/troubleshoot/azure/azure-monitor/log-analytics/windows-agents/ssl-connectivity-mma-windows-powershell

    try {
        $tcpSocket = New-Object Net.Sockets.TCPClient($hostToTest, $portToTest)
        $tcpStream = $tcpSocket.GetStream()
        $sslStream = New-Object -TypeName Net.Security.SSLStream($tcpStream, $false)
        $sslStream.AuthenticateAsClient($hostToTest)  # a missing or invalid cert here will cause an exception to be thrown

        $tlsCert = New-Object -TypeName Security.Cryptography.X509Certificates.X509Certificate2($sslStream.RemoteCertificate)
        $tcpSocket.Close()

        Write-Ok

        $fro.CertificateIssueDate = $tlsCert.NotBefore
        $fro.CertificateExpirationDate = $tlsCert.NotAfter
        $fro.CertificateThumbprint = $tlsCert.Thumbprint
        $fro.CertificateSerialNumber = $tlsCert.SerialNumber
        $fro.CertificatePublicKeyType = $tlsCert.PublicKey.Key.SignatureAlgorithm
        $fro.CertificatePublicKeyBits = $tlsCert.PublicKey.Key.KeySize
        $fro.Certificate = $tlsCert

        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed successfully!" "green"

        if($mrao){
            Write-CertifiCat $hostToTest $(get-date ($tlsCert.NotAfter) -format "MM/dd/yyyy")
        }

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $true $debugMode $debugLogDirectory
        }

        return $fro
      }
      catch {
        Write-Fail
        $fro.Errors += "Unable to establish a TLS connection to $($hostToTest):$portToTest`n$($_.Exception.Message)"
        $fro.FunctionSuccess = $false

        # close the socket if it's open
        if($tcpSocket.Connected){
            $tcpSocket.Close()
        }

        Write-FunctionBlock "[$($myinvocation.MyCommand)]" "Completed unsuccessfully!" "red"

        # write debug information if desired
        if($debugEnabled){
            Write-ACMEDebug $myInvocation.MyCommand $fro $false $debugMode $debugLogDirectory
        }

        return $fro
      }
}