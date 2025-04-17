# 1. Login to Azure using Managed Identity
Disable-AzContextAutosave -Scope Process
Connect-AzAccount -Identity

# 2. Get SMTP settings, company name, and subscription IDs from Automation Variables and Credential
$smtpServer    = Get-AutomationVariable -Name "SmtpServer"
$smtpPort      = Get-AutomationVariable -Name "SmtpPort"
$smtpFrom      = Get-AutomationVariable -Name "SmtpFrom"
$smtpTo        = Get-AutomationVariable -Name "SmtpTo"
$companyName   = Get-AutomationVariable -Name "CompanyName"
$subscriptionIdsRaw = Get-AutomationVariable -Name "SubscriptionIds"
$smtpCred      = Get-AutomationPSCredential -Name "SmtpCredential"
if (-not $smtpCred) {
    throw "The 'SmtpCredential' Automation Credential was not found!"
}

# 3. Split the subscription IDs string into an array (supports comma or semicolon separated)
$subscriptions = $subscriptionIdsRaw -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

# 4. Define HTML style
$htmlStyle = @"
<style>
    body {
        font-family: Arial, Helvetica, sans-serif;
        font-size: 14px;
        color: #333333;
    }
    h1 {
        color: #0072C6;
        font-size: 24px;
    }
    h2 {
        color: #2B579A;
        font-size: 20px;
        margin-top: 20px;
    }
    table {
        border-collapse: collapse;
        width: 100%;
        margin-bottom: 20px;
    }
    th {
        background-color: #0072C6;
        color: white;
        text-align: left;
        padding: 8px;
        border: 1px solid #dddddd;
    }
    td {
        padding: 8px;
        border: 1px solid #dddddd;
    }
    tr:nth-child(even) {
        background-color: #f2f2f2;
    }
    .warning {
        background-color: #FFF3CD;
    }
    .danger {
        background-color: #F8D7DA;
    }
    .summary {
        background-color: #E6F7FF;
        padding: 10px;
        border-radius: 5px;
        margin-bottom: 20px;
    }
    .no-resources {
        color: green;
        font-weight: bold;
    }
</style>
"@

# 5. Iterate through each subscription
foreach ($sub in $subscriptions) {
    Set-AzContext -SubscriptionId $sub
    $subName = (Get-AzSubscription -SubscriptionId $sub).Name
    
    # Initialize HTML body
    $htmlBody = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    $htmlStyle
</head>
<body>
    <h1>$companyName - Azure Erőforrás Jelentés</h1>
    <div class="summary">
        <strong>Előfizetés:</strong> $subName ($sub)<br>
        <strong>Dátum:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm")<br>
    </div>
"@

    $hasIssues = $false
    
    # Public IP addresses
    $unassignedIps = Get-AzPublicIpAddress | Where-Object { $_.IpConfiguration -eq $null }
    if ($unassignedIps -and $unassignedIps.Count -gt 0) {
        $hasIssues = $true
        $htmlBody += @"
    <h2>Nem hozzárendelt publikus IP-címek</h2>
    <table>
        <tr>
            <th>Név</th>
            <th>IP-cím</th>
            <th>Erőforráscsoport</th>
        </tr>
"@
        foreach ($ip in $unassignedIps) {
            $htmlBody += @"
        <tr class="danger">
            <td>$($ip.Name)</td>
            <td>$($ip.IpAddress)</td>
            <td>$($ip.ResourceGroupName)</td>
        </tr>
"@
        }
        $htmlBody += "</table>"
    }

    # Managed Disks
    $unassignedDisks = Get-AzDisk | Where-Object { $_.ManagedBy -eq $null }
    # Filter out ASR seed disks
    $unassignedDisks = $unassignedDisks | Where-Object { -not ($_.Name -like "asrseeddisk-*") }
    
    if ($unassignedDisks -and $unassignedDisks.Count -gt 0) {
        $hasIssues = $true
        $htmlBody += @"
    <h2>Nem hozzárendelt lemezek</h2>
    <table>
        <tr>
            <th>Név</th>
            <th>Méret (GB)</th>
            <th>Típus</th>
            <th>Erőforráscsoport</th>
        </tr>
"@
        foreach ($disk in $unassignedDisks) {
            $htmlBody += @"
        <tr class="danger">
            <td>$($disk.Name)</td>
            <td>$($disk.DiskSizeGB)</td>
            <td>$($disk.Sku.Name)</td>
            <td>$($disk.ResourceGroupName)</td>
        </tr>
"@
        }
        $htmlBody += "</table>"
    }

    # Network Interfaces (NIC)
    $unassignedNics = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine -eq $null }
    if ($unassignedNics -and $unassignedNics.Count -gt 0) {
        $hasIssues = $true
        $htmlBody += @"
    <h2>Nem hozzárendelt hálózati interfészek (NIC)</h2>
    <table>
        <tr>
            <th>Név</th>
            <th>Privát IP</th>
            <th>Erőforráscsoport</th>
        </tr>
"@
        foreach ($nic in $unassignedNics) {
            $privateIp = ($nic.IpConfigurations | Select-Object -First 1).PrivateIpAddress
            $htmlBody += @"
        <tr class="danger">
            <td>$($nic.Name)</td>
            <td>$privateIp</td>
            <td>$($nic.ResourceGroupName)</td>
        </tr>
"@
        }
        $htmlBody += "</table>"
    }

    # Network Security Groups (NSG)
    $unassignedNSGs = Get-AzNetworkSecurityGroup | Where-Object { $_.NetworkInterfaces.Count -eq 0 -and $_.Subnets.Count -eq 0 }
    if ($unassignedNSGs -and $unassignedNSGs.Count -gt 0) {
        $hasIssues = $true
        $htmlBody += @"
    <h2>Nem hozzárendelt hálózati biztonsági csoportok (NSG)</h2>
    <table>
        <tr>
            <th>Név</th>
            <th>Erőforráscsoport</th>
        </tr>
"@
        foreach ($nsg in $unassignedNSGs) {
            $htmlBody += @"
        <tr class="danger">
            <td>$($nsg.Name)</td>
            <td>$($nsg.ResourceGroupName)</td>
        </tr>
"@
        }
        $htmlBody += "</table>"
    }

    # Virtual Machines stopped but not deallocated - JAVÍTOTT RÉSZ
    $allVMs = Get-AzVM -Status
    $stoppedVMs = $allVMs | Where-Object { 
        $_.PowerState -eq "VM stopped" -and 
        (-not ($_.PowerState -eq "VM deallocated"))
    }
    
    # Ha nem találtunk, próbáljuk meg az eredeti módszerrel is
    if (-not $stoppedVMs -or $stoppedVMs.Count -eq 0) {
        $stoppedVMs = $allVMs | Where-Object {
            $_.Statuses | Where-Object { 
                $_.Code -eq "PowerState/stopped" -and 
                $_.DisplayStatus -eq "VM stopped"
            }
        }
    }
    
    if ($stoppedVMs -and $stoppedVMs.Count -gt 0) {
        $hasIssues = $true
        $htmlBody += @"
    <h2>Leállított (de nem felszabadított) virtuális gépek (továbbra is költségeket generálnak)</h2>
    <table>
        <tr>
            <th>Név</th>
            <th>Méret</th>
            <th>Állapot</th>
            <th>Erőforráscsoport</th>
        </tr>
"@
        foreach ($vm in $stoppedVMs) {
            $vmDetails = Get-AzVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName
            $vmStatus = ($vm.Statuses | Where-Object { $_.Code -like "PowerState*" }).DisplayStatus
            $htmlBody += @"
        <tr class="warning">
            <td>$($vm.Name)</td>
            <td>$($vmDetails.HardwareProfile.VmSize)</td>
            <td>$vmStatus</td>
            <td>$($vm.ResourceGroupName)</td>
        </tr>
"@
        }
        $htmlBody += "</table>"
    }

    # Add a message if no issues found
    if (-not $hasIssues) {
        $htmlBody += @"
    <div class="no-resources">
        <p>Nem találtunk nem hozzárendelt vagy problémás erőforrásokat ebben az előfizetésben.</p>
    </div>
"@
    }

    # Close HTML body
    $htmlBody += @"
</body>
</html>
"@

    # Send email with UTF-8 encoding
    $subject = "$companyName - Azure: Nem hozzárendelt/Leállított erőforrások jelentése ($subName)"
    
    # Create mail message with proper encoding
    $mailMessage = New-Object System.Net.Mail.MailMessage
    $mailMessage.From = $smtpFrom
    $mailMessage.To.Add($smtpTo)
    $mailMessage.Subject = $subject
    $mailMessage.Body = $htmlBody
    $mailMessage.IsBodyHtml = $true
    
    # Set encoding to UTF-8
    $mailMessage.BodyEncoding = [System.Text.Encoding]::UTF8
    $mailMessage.SubjectEncoding = [System.Text.Encoding]::UTF8
    
    # Create SMTP client
    $smtpClient = New-Object System.Net.Mail.SmtpClient($smtpServer, $smtpPort)
    $smtpClient.EnableSsl = $true
    $smtpClient.Credentials = New-Object System.Net.NetworkCredential($smtpCred.UserName, $smtpCred.Password)
    
    # Send mail
    try {
        $smtpClient.Send($mailMessage)
        Write-Output "[$subName] Jelentés elküldve. Talált problémák: $(if ($hasIssues) { 'Igen' } else { 'Nem' })"
    }
    catch {
        Write-Error "[$subName] Hiba történt az e-mail küldése közben: $_"
    }
    finally {
        $mailMessage.Dispose()
        $smtpClient.Dispose()
    }
}
