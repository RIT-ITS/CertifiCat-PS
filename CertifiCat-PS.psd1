@{
    RootModule = 'CertifiCat-PS.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'b596f403-1de9-415d-abb6-772f4293202a'
    Author = 'RIT Information and Technology Services'
    CompanyName = 'Rochester Institute of Technology'
    Description = 'Exension of the RIT CertifiCat server, used to manage the issuance and update of certificates on Windows servers by extending Posh-ACME'


    # Assemblies that must be loaded prior to importing this module
    #RequiredAssemblies = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Initialize-ACMEEnvironment',
        'Initialize-NewACMECertificate',
        'Confirm-ACMERenewalReadiness',
        'Initialize-ExistingACMECertificate',
        'Initialize-ACMEProxyRedirect',
        'Repair-NewACMEOrder',
        'Set-ACMEHome',
        'Enable-ACMEProxyRedirect',
        'Disable-ACMEProxyRedirect',
        'Assert-SiteCertificate',
        'Get-CertifiCatVariables',
        'Copy-CertifiCatSamples',
        'Set-CertifiCatDomainValidation'
    )

    PrivateData = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('acme', 'tls', 'ssl', 'certificat', 'certificate')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/RIT-ITS/CertifiCat-PS/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/RIT-ITS/CertifiCat-PS'
        }
    }

    # HelpInfo URI of this module
    HelpInfoUri = 'https://github.com/RIT-ITS/CertifiCat-PS'
}
