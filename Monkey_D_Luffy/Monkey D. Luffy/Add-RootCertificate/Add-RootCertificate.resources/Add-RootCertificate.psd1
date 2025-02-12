# Culture = "en-US"
ConvertFrom-StringData @'
###PSLOC
    PromptYesString = &Yes
    PromptNoString = &No
    CertificateFound = Found certificate: {0}
    InstallingCertificate = Installing certificate...
    InstallCertificateSuccessful = The certificate was successfully installed.
    Success = \nSuccess: Your certificate was successfully installed.
    WarningInstallCert = \nYou are about to install a digital certificate to your computer's Trusted Root Certification Authorities store. Doing so carries serious security risk and should only be done if you trust the originator of this digital certificate. Instructions for removing this certificate can be found here: http://go.microsoft.com/fwlink/?LinkId=243053\n\nAre you sure you wish to continue?\n\n
    ElevateActions = \nBefore installing this certificate, you need to do the following:
    ElevateActionsContinue = Administrator credentials are required to continue.  Please accept the UAC prompt and provide your administrator password if asked.
    ErrorForceElevate = You must provide administrator credentials to proceed.  Please run this script without the -Force parameter or from an elevated PowerShell window.
    ErrorLaunchAdminFailed = Error: Could not start a new process as administrator.
    ErrorNoScriptPath = Error: You must launch this script from a file.
    ErrorNoCertificateFound = Error: No certificate found in the script directory.
    ErrorManyCertificatesFound = Error: More than one certificate found in the script directory.
    ErrorBadCertificate = Error: The file "{0}" is not a valid digital certificate.  CertUtil returned with error code {1}.
    ErrorExpiredCertificate = Error: The certificate "{0}" has expired. One possible cause is the system clock isn't set to the correct date and time.
    ErrorInstallCertificateCancelled = Error: Installation of the certificate was cancelled.
    ErrorCertUtilInstallFailed = Error: Could not install the certificate.  CertUtil returned with error code {0}.
    ErrorInstallCertificateFailed = Error: Could not install the certificate. Status: {0}. For more information, see http://go.microsoft.com/fwlink/?LinkID=252740.
'@
