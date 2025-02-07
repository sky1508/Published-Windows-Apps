

param(
    [switch]$Force = $false,
    [switch]$GetDeveloperLicense = $false,
    [string]$CertificatePath = $null
)

$ErrorActionPreference = "Stop"

# The language resources for this script are placed in the
# "Add-RootCertificate.resources" subfolder alongside the script.  Since the
# current working directory might not be the directory that contains the
# script, we need to create the full path of the resources directory to
# pass into Import-LocalizedData
$ScriptPath = $null
try
{
    $ScriptPath = (Get-Variable MyInvocation).Value.MyCommand.Path
    $ScriptDir = Split-Path -Parent $ScriptPath
}
catch {}

if (!$ScriptPath)
{
    PrintMessageAndExit $UiStrings.ErrorNoScriptPath $ErrorCodes.NoScriptPath
}

$LocalizedResourcePath = Join-Path $ScriptDir "Add-RootCertificate.resources"
Import-LocalizedData -BindingVariable UiStrings -BaseDirectory $LocalizedResourcePath

$ErrorCodes = Data {
    ConvertFrom-StringData @'
    Success = 0
    NoScriptPath = 1
    NoCertificateFound = 4
    ManyCertificatesFound = 5
    BadCertificate = 6
    ForceElevate = 9
    LaunchAdminFailed = 10
    CertUtilInstallFailed = 17
    InstallCertificateCancelled = 22
    ExpiredCertificate = 24
'@
}

function PrintMessageAndExit($ErrorMessage, $ReturnCode)
{
    Write-Host $ErrorMessage
    if (!$Force)
    {
        Pause
    }
    exit $ReturnCode
}

#
# Warns the user about installing certificates, and presents a Yes/No prompt
# to confirm the action.  The default is set to No.
#
function ConfirmCertificateInstall
{
    $Answer = $host.UI.PromptForChoice(
                    "", 
                    $UiStrings.WarningInstallCert, 
                    [System.Management.Automation.Host.ChoiceDescription[]]@($UiStrings.PromptYesString, $UiStrings.PromptNoString), 
                    1)
    
    return $Answer -eq 0
}

#
# Validates whether a file is a valid certificate using CertUtil.
# This needs to be done before calling Get-PfxCertificate on the file, otherwise
# the user will get a cryptic "Password: " prompt for invalid certs.
#
function ValidateCertificateFormat($FilePath)
{
    # certutil -verify prints a lot of text that we don't need, so it's redirected to $null here
    certutil.exe -verify $FilePath > $null
    if ($LastExitCode -lt 0)
    {
        PrintMessageAndExit ($UiStrings.ErrorBadCertificate -f $FilePath, $LastExitCode) $ErrorCodes.BadCertificate
    }
    
    # Check if certificate is expired
    $cert = Get-PfxCertificate $FilePath
    if (($cert.NotBefore -gt (Get-Date)) -or ($cert.NotAfter -lt (Get-Date)))
    {
        PrintMessageAndExit ($UiStrings.ErrorExpiredCertificate -f $FilePath) $ErrorCodes.ExpiredCertificate
    }
}

#
# Performs operations that require administrative privileges:
#   - Prompt the user to obtain a developer license
#   - Install the developer certificate (if -Force is not specified, also prompts the user to confirm)
#
function DoElevatedOperations
{
    if ($CertificatePath)
    {
        Write-Host $UiStrings.InstallingCertificate

        # Make sure certificate format is valid and usage constraints are followed
        ValidateCertificateFormat $CertificatePath

        # If -Force is not specified, warn the user and get consent
        if ($Force -or (ConfirmCertificateInstall))
        {
            # Add cert to store
            certutil.exe -addstore Root $CertificatePath
            if ($LastExitCode -lt 0)
            {
                PrintMessageAndExit ($UiStrings.ErrorCertUtilInstallFailed -f $LastExitCode) $ErrorCodes.CertUtilInstallFailed
            }
            Pause
        }
        else
        {
            PrintMessageAndExit $UiStrings.ErrorInstallCertificateCancelled $ErrorCodes.InstallCertificateCancelled
        }
    }
}

#
# Launches an elevated process running the current script to perform tasks
# that require administrative privileges.  This function waits until the
# elevated process terminates, and checks whether those tasks were successful.
#
function LaunchElevated
{
    # Set up command line arguments to the elevated process
    $RelaunchArgs = '-ExecutionPolicy Unrestricted -file "' + $ScriptPath + '"'

    if ($Force)
    {
        $RelaunchArgs += ' -Force'
    }
    if ($NeedInstallCertificate)
    {
        $RelaunchArgs += ' -CertificatePath "' + $DeveloperCertificatePath.FullName + '"'
    }

    # Launch the process and wait for it to finish
    try
    {
        $AdminProcess = Start-Process "$PsHome\PowerShell.exe" -Verb RunAs -ArgumentList $RelaunchArgs -PassThru
    }
    catch
    {
        $Error[0] # Dump details about the last error
        PrintMessageAndExit $UiStrings.ErrorLaunchAdminFailed $ErrorCodes.LaunchAdminFailed
    }

    while (!($AdminProcess.HasExited))
    {
        Start-Sleep -Seconds 2
    }
}

#
# Main script logic when the user launches the script without parameters.
#
function DoStandardOperations
{
    # Test if the package signature is trusted.  If not, the corresponding certificate
    # needs to be present in the current directory and needs to be installed.
    $NeedInstallCertificate = ($PackageSignature.Status -ne "Valid")
    $NeedInstallCertificate = $true

    if ($NeedInstallCertificate)
    {
        # List all .cer files in the script directory
        $DeveloperCertificatePath = Get-ChildItem (Join-Path $ScriptDir "*.cer") | Where-Object { $_.Mode -NotMatch "d" }

        # There must be exactly 1 certificate
        if ($DeveloperCertificatePath.Count -lt 1)
        {
            PrintMessageAndExit $UiStrings.ErrorNoCertificateFound $ErrorCodes.NoCertificateFound
        }
        elseif ($DeveloperCertificatePath.Count -gt 1)
        {
            PrintMessageAndExit $UiStrings.ErrorManyCertificatesFound $ErrorCodes.ManyCertificatesFound
        }

        Write-Host ($UiStrings.CertificateFound -f $DeveloperCertificatePath.FullName)

        # The .cer file must have the format of a valid certificate
        ValidateCertificateFormat $DeveloperCertificatePath
    }

    # Relaunch the script elevated with the necessary parameters if needed
    if ($NeedInstallCertificate)
    {
        Write-Host $UiStrings.ElevateActions

        $IsAlreadyElevated = ([Security.Principal.WindowsIdentity]::GetCurrent().Groups.Value -contains "S-1-5-32-544")
        if ($IsAlreadyElevated)
        {
            if ($Force -and $NeedInstallCertificate)
            {
                Write-Warning $UiStrings.WarningInstallCert
            }
        }
        else
        {
            if ($Force)
            {
                PrintMessageAndExit $UiStrings.ErrorForceElevate $ErrorCodes.ForceElevate
            }
            else
            {
                Write-Host $UiStrings.ElevateActionsContinue
                Pause
            }
        }

        LaunchElevated
    }
}

#
# Main script entry point
#
if ($CertificatePath)
{
    DoElevatedOperations
}
else
{
    DoStandardOperations
}

# SIG # Begin signature block
# MIILOAYJKoZIhvcNAQcCoIILKTCCCyUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUVZym088yvZ2nx9nXZ1d7dH9g
# /kiggghnMIIELzCCAxegAwIBAgICAaEwDQYJKoZIhvcNAQELBQAwgZIxCzAJBgNV
# BAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3JhdGlvbjEuMCwGA1UECxMl
# V2luZG93cyBQaG9uZSBFbnRlcnByaXNlIEFwcGxpY2F0aW9uczE0MDIGA1UEAxMr
# U3ltYW50ZWMgRW50ZXJwcmlzZSBNb2JpbGUgQ0EgZm9yIE1pY3Jvc29mdDAeFw0x
# MzA2MDgxNjQ5MzhaFw0xNDA2MTIwOTE3NTdaMFkxHjAcBgNVBAsTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEeMBwGA1UEAxMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMRcw
# FQYKCZImiZPyLGQBARMHNTM0MjI1ODCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
# AQoCggEBAMRwDmdC0d3YFQsN7aUfwwXp5OdH4f+bUfZRLdykKkTKs2eQFLtQ/zTH
# IhnLDVV1GgclkMyCFuqX6MjeEVUyB4RqKRobB514qkmYHgRuLzzgKrtR0WEK/p1A
# pz6QOTRoNF1XF+F6j+DJ0jDXZWLoxytWXkN2xqBbVdc5uFLA4wU6/gEajyebS9ar
# h4nY0MY8lPpqDMJMYQ5T15U0tjkuY7QkWNr/0hFzVgydZDTrojncaiJguZndDhc+
# cTKuu8GJjydQoAqByXcRnpHKK4cyXgbT62ERYjUKXqUEZaTFXttgrjtycd9U34/y
# 4tnSQ62m/ojr/R2Kh18rxiI4BZ69f+ECAwEAAaOBxjCBwzAfBgNVHSMEGDAWgBRc
# KmQbWRIO6nCAIRQ4Uq0IyemWgDAOBgNVHQ8BAf8EBAMCB4AwIAYDVR0lBBkwFwYI
# KwYBBQUHAwMGC2CGSAGG+EUBCDQBMEEGA1UdHwQ6MDgwNqA0oDKGMGh0dHA6Ly9j
# cmwuZ2VvdHJ1c3QuY29tL2NybHMvbXNmdGVudG1vYmlsZWNhLmNybDAMBgNVHRMB
# Af8EAjAAMB0GA1UdDgQWBBQJBMeFf/uB1xVGq5DI9nboYNq6mzANBgkqhkiG9w0B
# AQsFAAOCAQEAHQWGsBjcqdh+azB2t0lWDBI1aIE6UfT9r2TbKA7jdv4svNJDb+s/
# fN+ves2tRjWnXh6HKLZqSdlZTOshw21WU14A5mIM6tL5WF/QzvYyiNGLp0SUMkjR
# uzED9ZODkHIdWmBkACKZFXOvj46MlOTfKaRPuvOGSDbKdldUcwVjTwQjglzScNaR
# 4N/yt3alEE1CMcercaJEglHNjlsK/PVd0aSSV3xta6coLpTDYEVPxn2xBuPwmIxr
# zTxuBHT2cRjCwX8hl/dFAqH/xc0PXT3lAUo6C066oiDgrSCX0aHFqYSf4NeSlzT9
# 4WYMk+nQ0tPKrUoWjv7WuQ9VIK+38fBnGTCCBDAwggMYoAMCAQICECXnGfAo/xse
# HSeXuZNpW2wwDQYJKoZIhvcNAQELBQAwZDELMAkGA1UEBhMCVVMxHTAbBgNVBAoT
# FFN5bWFudGVjIENvcnBvcmF0aW9uMTYwNAYDVQQDEy1TeW1hbnRlYyBFbnRlcnBy
# aXNlIE1vYmlsZSBSb290IGZvciBNaWNyb3NvZnQwHhcNMTIwMzE1MDAwMDAwWhcN
# MjcwMzE0MjM1OTU5WjCBkjELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVj
# IENvcnBvcmF0aW9uMS4wLAYDVQQLEyVXaW5kb3dzIFBob25lIEVudGVycHJpc2Ug
# QXBwbGljYXRpb25zMTQwMgYDVQQDEytTeW1hbnRlYyBFbnRlcnByaXNlIE1vYmls
# ZSBDQSBmb3IgTWljcm9zb2Z0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKC
# AQEAsmlJTN1CkJj+qshu6dx+Z/Ldc4KKWkAvteXgVwohlnkT80d+GFcc6PNEWGIt
# K39CrTvX5OXpve3i+HM0DoVDzKvsLfbdCww39AaUu/WFvgrx1aZNwYcg3ui4/y4g
# USH+hHPhBnNbGv//OUOciKjk3dTUAGwHGdcfRvduZHVyp94+k+e4+Wvucjwcfc2e
# CbAb5vrAMya+N+8nIZPo6cKTeQSy1hdhipxBV5XCWD23qCMiHxapMNWiT04Lq5NF
# yYFSFmY90zB7cPq5OLR9dG9DXpaUWRcGv+PLFXy6uaDxyn4uEpEen6+GwH4wnboC
# a/G8uMov8KmBBdp909m/tqXZJQIDAQABo4GuMIGrMBIGA1UdEwEB/wQIMAYBAf8C
# AQAwRQYDVR0fBD4wPDA6oDigNoY0aHR0cDovL2NybC5nZW90cnVzdC5jb20vY3Js
# cy9tc2Z0ZW50bW9iaWxlcm9vdGNhLmNybDAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0O
# BBYEFFwqZBtZEg7qcIAhFDhSrQjJ6ZaAMB8GA1UdIwQYMBaAFE3s3yYG3CQQwLaZ
# 9Nc5x28Z+CYoMA0GCSqGSIb3DQEBCwUAA4IBAQCWB0gBlniSHU7E87O3awqCiA3h
# othUyucxn4YgGNfKI0TD87Ar2l0VRqRaWsvhqthMDXQaKbIM9dtTZXeAGUqmCZcf
# TQi1QJTfcnsQyqJN1hvZ08mdtxKTBA/2twrDgu/eiGFpprpfMpJvwV4bDjvi/UuY
# BdP6IxffPVEKz6BJth2SvAlkzk+bRgk2R0jem00gANIr5HYtITkD5T2B/q/+6M5A
# 8rADx1Yq6lmzzOmIg7XKW1sCE81iO3LnP+cSULB6XYCN6d3KnBzeUb5HLy8HosWQ
# j4QdEEchk8fkwsKJFp/m8unxH8Br03+dMxdLgaZf8I/81Hfau0g05j04+vaCMYIC
# OzCCAjcCAQEwgZkwgZIxCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBD
# b3Jwb3JhdGlvbjEuMCwGA1UECxMlV2luZG93cyBQaG9uZSBFbnRlcnByaXNlIEFw
# cGxpY2F0aW9uczE0MDIGA1UEAxMrU3ltYW50ZWMgRW50ZXJwcmlzZSBNb2JpbGUg
# Q0EgZm9yIE1pY3Jvc29mdAICAaEwCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwx
# CjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGC
# NwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFDUBycDPe9gHoNWn
# Sk26kaMmULblMA0GCSqGSIb3DQEBAQUABIIBAE3MuuRm/Kw2ZWmtTzNKd4Fe0VGk
# RXbg9vtLs4PpVBDOTu4ksekPU8/v8nDfV7DiaSxMl668WEBtOJ9nVZBm10ralRgE
# UbU2Y1hgp+ZmAgUsqkdPTHTVotUZNh+MPLe2QDbtbtWT+mqN+BEbMAMC0J9ITxgQ
# NSdrtaVhpNdwgHkybYqQLhnZuJexfthwIkCHBqecPyh5BQmo/kkztGmveNdOIWk5
# sLm9EP3F9bcL448+ZPFHDOCT13xAmKWiDJ2lrRCxfqspWCYWAMWRg7EfBFtARE/N
# 4fckRcxEuEFzzOvNe1LQTmqZF809prQzoiVtCnh2oiu8/2Tbq+Z//msLsno=
# SIG # End signature block
