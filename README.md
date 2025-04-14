# CertifiCat-PS

## Overview

Rochester Institute of Technology’s CertifiCat-PS module is designed to extend the [Posh-ACME](https://poshac.me/docs/v4/) module, used to obtain certificates from an ACME-compatible server. While the module is being released alongside RIT's [CertifiCat server](https://github.com/RIT-ITS/CertifiCat), CertifiCat-PS can be used with any ACME-compatible client, as it uses Posh-ACME as the underlying mechanism to request certificates. 

CertifiCat-PS extends Posh-ACME in a number of ways, including:

- Performing the update of IIS certificate bindings after obtaining a new certificate
- Backing up all issued certificates to a central directory
- Easing the setup of Posh-ACME, including installing prerequsites, connecting to your ACME server, and creating a local ACME account, in a single function
- Aiding in the HTTP challenge process, in cases where a certificate is requested for servers that are part of a pool or farm environment
- Decoupling the process of requesting a certificate from a specific back-end module or process (currently being done via Posh-ACME)
- Performing optional validation on all SANs in a certificate request to ensure that they comport with an organization's domain names

## License
CertifiCat-PS is licensed under the Apache 2.0 license.

## Getting Help
Use the GitHub issues feature if you encounter a bug or have questions. We’ll do our best to provide answers.

## Supporting the Project
GitHub pull requests are welcomed. If you have an idea, submit it as an issue, and we’ll look it over. If you want to help with more than bug fixes or ideas, contact the project owners at its-acme@rit.edu.

# Quick Start
For more information, use cases (including requesting certificates for servers as part of a pool or farm), and documentation on all of the CertifiCat-PS functions, please view the wiki associated with this repository.

CertifiCat-PS also ships with a number of sample implementation scripts, intended to jumpstart the process of automating certificate renewals.

Use the following steps to get started with CertifiCat-PS using the sample scripts:

1. Configure an account on your CertifiCat server - specifically, you will need the Account Key and Account ID

2. Install the CertifiCat-PS Module:

```pwsh
Install-Module CertifiCat-PS -Scope AllUsers
```

3. Set up the ACME environment. This includes:
- Installing Posh-ACME 
- Configuring a central ACME working directory in `%PROGRAMDATA%\certificat-ps\posh-acme` (as Posh-ACME defaults to the current user's local appdata directory)
- Creating a connection to your CertifiCat server (by default, if the -ACMEServer parameter below is omitted, the function defaults to https://acme.rit.edu)
- Creating a local account based on the account key and ID obtained in step 1

```pwsh
Initialize-ACMEEnvironment -ACMEServer https://certificat.example.com -PAUserID "My-ACME-Account-ID" -PAUserKey "My-ACME-Account-Key"
```

4. Extract the sample scripts that ship with the CertifiCat-PS module to an appropriate directory

```pwsh
Copy-CertifiCatSamples -outputDirectory "c:\certificat-ps\samples"
```

5. Choose the sample script appropriate for your situation, and make the relevant updates. Minimially, this includes modifying the `SCRIPT VARIABLES` section, but may also include one or more `CUSTOM LOGIC` blocks. Currently, CertifiCat-PS ships with the following sample files:

| File Name                             | Use Case                                                                                                                                       | 
| --------------------------------------| ---------------------------------------------------------------------------------------------------------------------------------------------- | 
| Custom-SingleServerUsingCertFile.ps1  | Standalone servers requiring custom work as part of an application, where the app references the certificate via a certificate file.           |
| Custom-SingleServerUsingCertStore.ps1 | Standalone servers requiring custom work as part of an application, where the app references the certificate in the Windows Certificate Store. |
| IIS-MultipleServers.ps1               | Servers running IIS as part of a pool. Be sure to review the wiki for information about requesting certificates as part of a farm.             |
| IIS-SingleServer.ps1                  | Standalone servers running IIS. |

6. If desired, move the newly updated sample script to an appropriate location, and either run it, or schedule it via the Windows Task Scheduler

