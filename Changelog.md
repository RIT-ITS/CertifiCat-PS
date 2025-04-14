# Changelog

## Module Changes
### 1.0.0
- (Change) Updating module versioning from [year.month.day.release] to SemVer-compatible values [major.minor.patch], per the [PowerShellGallery Best Practices](https://learn.microsoft.com/en-us/powershell/gallery/concepts/publishing-guidelines?view=powershellget-3.x)
- (Change) Fixed the ps5Command property of the return object on all functions to account for the change in name from ps-acme -> CertifiCat-PS
- (Change) Set the DontShow attribute on the -ChainedCall parameter of `Confirm-ACMERenewalReadiness` since it will only be used in a private capacity
- (Fix) Added standard properties to the function return object in `Get-CertifiCatVariables`
- (Fix) Added the -SkipImport parameter to the `Custom-SingleServerUsingCertFile` sample script, since the use case here is to work from a certificate file, not the certificate store

### 25.3.3.1
- (Enhancement) Eliminated the need to re-launch PowerShell after running `Set-ACMEHome`. The new POSHACME_HOME variable will be respected by Posh-ACME immediately, as well as stored in the system environment variable for long-term use. ([Issue #34](https://gitlab.code.rit.edu/its-operations/certificat-ps/-/issues/34))
- (Enhancement) Simplified the CertifiCat-PS setup process by automatically calling the `Set-ACMEHome` function as part of running `Initialize-ACMEEnvironment`. `Set-ACMEHome` can still be used as needed, for example, if a user wishes to switch between two ACME servers/accounts, such as a test and production environment. ([Issue #14](https://gitlab.code.rit.edu/its-operations/certificat-ps/-/issues/14))
- (Enhancement) Created a new function, `Copy-CertifiCatSamples`, which can be used to quickly copy all sample files that ship with the module, to a specified directory. This negates the need to find the samples in the module's installation directory. ([Issue #33](https://gitlab.code.rit.edu/its-operations/certificat-ps/-/issues/33))
- (Enhancement) Added the ability to specify additional parameters as part of `Initialize-NewACMECertificate` that will be directly passed to Posh-ACME's `New-PACertificate` function. This allows users to expand the capabilities of the CertifiCat-PS module using parameters provided by Posh-ACME that we aren't directly exposing. ([Issue #28](https://gitlab.code.rit.edu/its-operations/certificat-ps/-/issues/28))
- (Enhancement) Added support for Posh-ACME's `-CertKeyLength` parameter in our `Initialize-NewACMECertificate` function. The default value for this parameter is (a) specified via a new variable in the module's manifest file (and thus also configurable via an environment variable), and (b) different that Posh-ACME's default value (as of 4/2/25, Posh-ACME defaults to a 2048-bit RSA key, while we will ship with a 4098 bit RSA key by default). ([Issue #21])(https://gitlab.code.rit.edu/its-operations/certificat-ps/-/issues/21)
- (Enhancement) Updated the `-CentralDirectory` parameter in the `Initialize-NewACMECertificate` function, such that the default is no longer hard-coded, but specified via a new variable in the module's manifest file (and which can be specified via an environment variable, in-line with the change in Issue #18, also part of this release). ([Issue #23](https://gitlab.code.rit.edu/its-operations/certificat-ps/-/issues/23))
- (Enhancement) Added a `-Jitter` parameter to the `Initialize-NewACMECertificate` function, which allows the user to specify a value which introduces a random delay (in seconds) between 1 and the provided value, before the function calls Posh-ACME to request a new certificate. This is useful in cases where there are multiple servers that need to request certificates simultaneously, and is an option beyond using jitter option the native Windows Task Scheduler. ([Issue #27](https://gitlab.code.rit.edu/its-operations/certificat-ps/-/issues/27))
- (Enhancement) Added optional debug logging to all module functions, to allow for the function's return object to be logged to a file and/or the Windows Event Log ([Issue #12](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/12))
- (Enhancement) Removed hard coded domain validation regex as part of `Initialize-NewACMECertificate` to a variable that can be configured via the module's main manifest file and a system environment variable ([Issue #15](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/15))
- (Enhancement) Created new private `Initialize-CertificatVariables` function to allow for module default variables to be specified and read from environment variables, in addition to the module's main manifest file. Also created a corresponding public function `Get-CertifiCatVariables` function to allow a user to read the value of each variable, if needed for verification purposes. ([Issue #18](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/18))
- (Change) Module has been renamed from **ps-acme** to **certificat-ps** to better align with our open-sourcing efforts and the formalization of the CertifiCat branding across the various components. ([Issue #17](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/17))
- (Change) Renamed the `-AllowNonRITDomain` parameter in the `Initialize-NewACMECertificate` function to `-SkipDomainValidation` to eliminate the RIT-specific verbiage throught the module as part of our open-sourcing efforts. ([Issue #16](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/16))
- (Security) Created new script used as part of the module build/commit process to update a new `hashes.sha256` file containing the SHA256 hashes of all module files, useful for verifying the security and integrity of the files. ([Issue #19](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/19))
- (Fix) Corrected an issue where the `Confirm-ACMERenewalReadiness` function may have returned an incorrect "ready to renew" result when a `-RenewalMethod` of "Directory" or "IIS" was used. ([Issue #31](https://gitlab.code.rit.edu/its-operations/certificat-ps/-/issues/31))

### 24.11.1.1
- (Enhancement) Added a step during the load of all public and private functions to check for Mark-of-The-Web / files being blocked, which will prevent the function from working as expected. ([Issue #11](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/11))
- (Enhancement) Removed the `-Contact` parameter from the `Initialize-ACMEEnvironment` function, as this account address is not used from an RIT ACME perspective. ([Issue #13](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/13))

### 24.9.27.1
- (Fix) Removed errant debug statements in `Initialize-NewACMECertificate` that prevented it from completing successfully ([Issue #8](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/8))
- (Fix) Corrected an issue with the `CentralDirectory` parameter of the `Repair-NewACMEOrder` function introduced in the last build that caused it to calculate incorrectly, thereby storing certificates in the wrong directory ([Issue #7](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/7))

### 24.9.19.1
- (Enhancement) Added check in the `Enable-ACMEProxyRedirect` and `Disable-ACMEProxyRedirect` functions to validate remote connectivity. ([Issue #1](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/1))
- (Enhancement) Parameterized the renewal threshold in `Confirm-ACMERenewalReadiness` and `Initialize-NewACMECertificate`. ([Issue #5](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/5))
- (Enhancement) Added new function called [`Assert-SiteCertificate`](https://gitlab.code.rit.edu/its-operations/ps-acme/-/wikis/Functions/AssertSiteCertificate) to query a server's TLS certificate. ([Issue #3](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/3))
- (Enhancement) Split out the module's functions into separate ps1 files, located in separate Public and Private directories, accessed via dot-sourcing in the main module file. ([Issue #4](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/4))
- (Fix) Added checks where appropriate to ensure that Posh-ACME is available when needed. ([Issue #2](https://gitlab.code.rit.edu/its-operations/ps-acme/-/issues/2))

### 24.8.28.1
- (Enhancement) Added a new function called `Enable-ACMEProxyRedirect` to allow the challenge proxy URL Rewrite Rule to be enabled as needed
- (Enhancement) Added a new function called `Disable-ACMEProxyRedirect` to allow the challenge proxy URL Rewrite Rule to be disabled as needed
- (Change) Added the -AlwaysNewKey parameter to the Posh-ACME command in Initialize-NewACMECertificate

### 24.8.5.1
- (Fix) Corrected the ps5Command parameter for all function return objects to correctly output the path to ps-acme module.

### 24.7.11.1
- (Enhancement) Added Reminder to Relaunch Terminal After Running Set-ACMEHome
- (Enhancement) Created a New -ExternalHooks Parameter for Downstream Actions
- (Change) Narrowed Scope Of URL Rewrite Rule in Initialize-ACMEProxyRedirect

### 24.7.3.1
- (Enhancement) Added Certificate FriendlyName to Function Return Object
- (Fix) Constrain Orders Refreshed by Repair-NewACMEOrder
- (Fix) Corrected Duplicate 'Copying Certificate' Output
- (Fix) Corrected Modern PowerShell Error Messaging

### 24.6.18.1
- (Enhancement) Added Function to Specify Posh-ACME Home/Working Directory
- (Fix) Fixed IIS Site Binding Thumbprint
- (Change) Confirm-ACMERenewalReadiness Defaults to Not Ready to Renew


## Sample Scripts

### 8/5/24
#### Both Single and Multiple Server Scripts
- Removed the certificate expiration date from displaying when the environment is ready for renewal. This is due to the fact that (currently), the ps-acme module won't return any certificate objects when renewal is ready.
- Enhanced the Slack message to include a link to crt.sh for the newly issued certificate, and listed all SANs on the newly issued certificate.
- Updated the primary domain (where the script is running from) in the Slack message to be a fully qualified domain name, rather than just the hostname
- Uncommented the Slack webhook URL variable