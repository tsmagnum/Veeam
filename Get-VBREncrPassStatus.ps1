<#
.SYNOPSIS
This scripts creates a report containing the Encryption Passwords used in Veeam Backup & Replication and their age in days
(from the last modification), to quickly check if someone modified them in the previous days. 
The script can be scheduled and configure to send an email.

.DESCRIPTION
This scripts creates a report containing the Encryption Passwords used in Veeam Backup & Replication and their age in days, 
to quickly check if someone modified them in the previous days. The script can be scheduled and configure to send an email.
The script requires a Microsoft Secret Store Vault configured, in order to store and retrieve safely the credentials.
Please see the NOTES section for more info.
All the user-variables (Credentials, API Server and Email) must be set before running the script!
The report lists the Encryption Passwords using their "Hint", their age in days (from the last modification) and their
alphanumeric Id. 

.NOTES
A Microsoft Secret Store Vault is required to store and retrieve safely the credentials: please read this article to configure
the vault https://adamtheautomator.com/powershell-encrypt-password/ . The $vaultPass variable has to be set to the full path 
to the XML Secret Store Master Password. 
The vault should contain the credentials to access the Veeam API server (variable $secretApiName) and the credentials required 
to connect to the SMTP server (variable $secretEmailName). You can easily get this values using the 'Get-SecretInfo' cmdlet, 
'Name' property.

Author: Federico Lillacci - Coesione Srl - https://github.com/tsmagnum

Link - https://github.com/tsmagnum/Veeam/blob/main/Get-VBREncrPassStatus.ps1
#>

#TLS Settings required
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#region user-variables Credentials
#full path to the XML containing the vault master password in the next line
$vaultPass = "./vaultpassword.xml"
#the values for the following lines can be obtained using 'Get-SecretInfo' cmdlet
#please read the NOTES section above!
$secretApiName = "ApiCredsSecret"
$secretEmailName = "SmtpCredsSecret"
#endregion

#region user-variables API Server (MANDATORY!)
#the Veeam B&R server hostname
$vbrServer = "localhost"
#endregion

#region user-variables - Email Settings
#set to true the following line to send the results via email
$emailReport = $true
$emailHost = "smtp.domain.com"
$emailPort = 587 
$emailEnableSSL = $true
$emailFrom = "sender@domain.com"
#insert one ore more recipients, enclosed in "", comma separated
$emailToAddresses = @("recipient@domain.com") 
$emailSubject = "Veeam B&R Encryption Password Monitor"
#endregion

#Getting today's date
$today = Get-Date

#Setting the URI
$uri = "https://"+$vbrServer+":9419/api"

#region CSS Code - to style the email report
$headerHTML = @"
<style>
    body
  {
      background-color: White;
      font-size: 12px;
      font-family: Arial, Helvetica, sans-serif;
  }

    table {
      border: 0.5px solid;
      border-collapse: collapse;
      width: 100%;
    }

    th {
        background-color: CornflowerBlue;
        color: white;
        padding: 6px;
        border: 0.5px solid;
        border-color: #000000;
    }

    tr:nth-child(even) {
            background-color: #f5f5f5;
        }

    td {
        padding: 6px;
        margin: 0px;
        border: 1px solid;
}

    h2{
        background-color: CornflowerBlue;
        color:white;
        text-align: center;
    }
</style>
"@
#endregion

#region HTML Code - for the email report
$preContent = "<h2>Veeam B&R Encryption Password on $($vbrServer)</h2>"
$postContent = "<p>Creation Date: $($today)<p>"
$title = "Veeam B&R Encryption Password Monitor"
#endregion

################# DO NOT MODIFY ANYTHING BEYOND THIS LINE! #################

#Using safely stored credentials to access the APIs 
#Please see https://adamtheautomator.com/powershell-encrypt-password/ to configure the vault
$vaultpassword = (Import-CliXml $vaultPass).Password
Unlock-SecretStore -Password $vaultpassword
$apiCreds = (Get-Secret -Name $secretApiName).GetNetworkCredential() | Select-Object Username,Password
$emailCreds = (Get-Secret -Name $secretEmailName).GetNetworkCredential() | Select-Object Username,Password

#Getting the authorization token
$authHeaders = @{
    "x-api-version" = "1.0-rev2"
    }

$authbody = @"
grant_type=password&username=$($apiCreds.UserName)&password=$($apiCreds.Password)
"@

try {
    $token = Invoke-RestMethod -Uri $uri/oauth2/token `
                -Method POST -Headers $authHeaders -Body $authBody -Verbose -SkipCertificateCheck
}
catch{
        Write-Host "The attempted operation failed" -ForegroundColor Red
        Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red
}

#Setting the authorization header
$requestHeaders = @{
    "Authorization" = "Bearer " + $token.access_token
    "x-api-version" = "1.0-rev2"
}

#Getting the encrypted passwords list
try {
    $encryptionPasswords = (Invoke-RestMethod -Uri $uri/v1/encryptionPasswords `
                                -Method GET -Headers $requestHeaders -ContentType "application/json" -SkipCertificateCheck).data
    }
catch {
        Write-Host "The attempted operation failed" -ForegroundColor Red
        Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red
    }

$reportPasswords = @()

#Creating a custom object with the encrypted password name and age in days
foreach ($encryptionPassword in $encryptionPasswords)
{
    $passwordAge = [DateTime]$encryptionPassword.modificationTime
    
    $reportPassword = [PSCustomObject]@{
    Password = $encryptionPassword.hint
    AgeInDays = ($today - $passwordAge).Days
    VeeamId = $encryptionPassword.Id
    }

    $reportPasswords += $reportPassword
}

#Displaying the results
$reportPasswords

#region Email
if ($emailReport -eq $true)
{
        $emailBody = ""
        $emailBody += $reportPasswords | ConvertTo-Html -PreContent $preContent -PostContent $postContent -Title $title -Head $headerHTML
        $emailBody += "</br></br><hr>"


        $smtp = New-Object System.Net.Mail.SmtpClient($emailHost, $emailPort)
        $smtp.Credentials = New-Object System.Net.NetworkCredential($emailCreds.UserName, $emailCreds.Password)
        $smtp.EnableSsl = $emailEnableSSL

        foreach ($emailTo in $emailToAddresses) 
            {
                try {
                    $msg = New-Object System.Net.Mail.MailMessage($emailFrom, $emailTo)
                    $msg.Subject = $emailSubject
                    $msg.Body = $emailBody
                    $msg.isBodyhtml = $true
                    $smtp.send($msg)
                    }
                catch {
                    Write-Host "The attempted operation failed" -ForegroundColor Red
                    Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red
                    }
            }
}
#endregion
