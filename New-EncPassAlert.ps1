<#
.SYNOPSIS
This scripts sends an email containing the log messages related to a successful Veeam encryption password modification.
The script must be attached to a 31700 event in the "Veeam Backup" as a task, with a "Start a program action" to run this PS1 script.
The email settings are MANDATORY!

.DESCRIPTION
This scripts sends an email containing the log messages related to a successful Veeam encryption password modification.
The script must be attached to a 31700 event in the "Veeam Backup" as a task, with a "Start a program action" to run this PS1 script.
The email settings are MANDATORY!

Author: Federico Lillacci - Coesione Srl - https://github.com/tsmagnum
#>

#region User-variables - Email Settings (MANDATORY!)
$emailHost = "smtp.domain.com"
$emailPort = 587 
$emailEnableSSL = $true
$emailUser = "yourSmtpUser"
$emailPass = "yourSmtpPassword"
$emailFrom = "sender@domain.com"
#insert one ore more recipient, enclosed in "", comma separated
$emailToAddresses = @("recipient@domain.com") 
$emailSubject = "WARINING - Veeam encryption password modified or created!"
#endregion

$timeFrame = (Get-Date).AddHours(-6)
$messages = Get-WinEvent -FilterHashtable @{Logname="Veeam Backup"; ID='31700','31600'; StartTime=$timeFrame}

$emailBody = ""

foreach ($message in $messages) 
    {

        $emailBody += "<strong>Veeam server: $($message.MachineName.ToString())</strong></br></br>"
        $emailBody += "Log message: $($message.Message)</br></br>"
        $emailBody += "Event logged at <strong>$($message.TimeCreated.ToString())</strong></br></br>"
        $emailBody += "<hr>"

    }

#region Sending email alert
$smtp = New-Object System.Net.Mail.SmtpClient($emailHost, $emailPort)
$smtp.Credentials = New-Object System.Net.NetworkCredential($emailUser, $emailPass)
$smtp.EnableSsl = $emailEnableSSL

foreach ($emailTo in $emailToAddresses) 
    {
        $msg = New-Object System.Net.Mail.MailMessage($emailFrom, $emailTo)
        $msg.Subject = $emailSubject
        $msg.Body = $emailBody
        $msg.isBodyhtml = $true
        $smtp.send($msg)
    }
#endregion