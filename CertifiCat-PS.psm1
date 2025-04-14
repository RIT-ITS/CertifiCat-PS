[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports coloring')]
param()

# Get public and private function definition files.
$Public  = @( Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction Ignore )
$Private = @( Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction Ignore )

# we need to keep track of the module's root directory for later on, but
# powershell doesn't natively have a 'PSModuleRoot' so we're creating one
# https://github.com/PowerShell/PowerShell/issues/9927
$script:PSModuleRoot = $PSScriptRoot

# Dot source the files
Foreach($import in @($Public + $Private))
{
    Try {
        # check to make sure that the module file is not blocked with a MoTW / Mark-of-The-Web
        # for security, we won't just blindly unblock the file, but will alert the user

        $motw = Get-Item $import.fullname -Stream "Zone.Identifier" -ErrorAction SilentlyContinue
        if($null -ne $motw){
            Write-Host "FATAL! Module file '$($import.fullname)' appears to be blocked! Was it downloaded from the internet without unblocking first?`nIf you have verified the safety of the file, it can be unblocked via the Unblock-File command, or right clicking the file and going to Properties." -ForegroundColor Red
            throw
        }

        . $import.fullname

    }
    Catch
    {
        Write-Error -Message "Failed to import function $($import.fullname): $_"
    }
}

# Set module-wide defaults and validate sets/patterns we'll use later
$script:DEFAULT_ACME_SERVER = "https://acme.rit.edu/directory"
$script:DEFAULT_POSHACME_HOME = "$($env:ProgramData)\CertifiCat-PS\posh-acme"
$script:DEFAULT_CERTIFICATE_STORE_NAME = "WebHosting"
$script:DEFAULT_CERTIFICATE_STORE_LOCATION = "LocalMachine"
$script:DEFAULT_IIS_WEBSITE = "Default Web Site"
$script:DEFAULT_RENEWAL_METHOD = "PA"
$script:DEFAULT_RENEWAL_DIRECTORY = "$($env:ProgramData)\CertifiCat-PS\certificates"
$script:DEFAULT_RENEWAL_THRESHOLD = 14
$script:DEFAULT_URL_REWRITE_RULE_NAME = "ACME Challenge Proxy"
$script:DEFAULT_URL_REWRITE_INSTALLER_LOG = "$($env:ProgramData)\CertifiCat-PS\logs\urlRewriteInstaller.log"
$script:DEFAULT_URL_REWRITE_INSTALLER_MSI = "$env:temp\rewrite_amd64_en-US.msi"
$script:DEFAULT_URL_REWRITE_INSTALLER_DOWNLOAD_URL = "https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi"
$script:DEFAULT_URL_REWRITE_INSTALLER_EXPECTED_HASH = "37342FF2F585F263F34F48E9DE59EB1051D61015A8E967DBDE4075716230A32A"
$script:DEFAULT_DEBUG_LOG_DIRECTORY = "$($env:ProgramData)\CertifiCat-PS\logs\debug"
$script:DEFAULT_EVENT_LOG_SOURCE = "CertifiCat-PS"
$script:DEFAULT_DEBUG_MODE = "EVT"
$script:DEFAULT_JITTER = 0
$script:DEFAULT_CERT_KEY_LENGTH = 4096
$script:DEFAULT_CENTRAL_DIRECTORY = "$($env:ProgramData)\CertifiCat-PS\certificates"

$script:VALIDATE_SET_DEBUG_MODE = "EVT", "File", "Both"
$script:VALIDATE_SET_RENEWAL_METHOD = "PA", "IIS", "Directory"
$script:VALIDATE_SET_CERTIFICATE_STORE_NAME = "WebHosting", "My", "Root"
$script:VALIDATE_SET_CERTIFICATE_STORE_LOCATION = "LocalMachine", "My"

$script:VALIDATE_PATTERN_PFX_PATH = "(.)*\.pfx"
$script:VALIDATE_PATTERN_DOMAIN_NAME = "(.)*.rit.edu"

# check to see if there are any environment variables that should override the defaults we set above
Initialize-CertifiCatVariables