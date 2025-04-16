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

# 4. Iterate through each subscription
foreach ($sub in $subscriptions) {
    Set-AzContext -SubscriptionId $sub

    $body = ""
    $subName = (Get-AzSubscription -SubscriptionId $sub).Name

    # Public IP addresses
    $unassignedIps = Get-AzPublicIpAddress | Where-Object { $_.IpConfiguration -eq $null }
    if ($unassignedIps) {
        $body += "`nUnassigned Public IP addresses:`n"
        foreach ($ip in $unassignedIps) {
            $body += "  - $($ip.Name) ($($ip.IpAddress)) in resource group $($ip.ResourceGroupName)`n"
        }
    }

    # Managed Disks
    $unassignedDisks = Get-AzDisk | Where-Object { $_.ManagedBy -eq $null }
    if ($unassignedDisks) {
        $body += "`nUnassigned Managed Disks:`n"
        foreach ($disk in $unassignedDisks) {
            $body += "  - $($disk.Name) in resource group $($disk.ResourceGroupName)`n"
        }
    }

    # Network Interfaces (NIC)
    $unassignedNics = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine -eq $null }
    if ($unassignedNics) {
        $body += "`nUnassigned Network Interfaces (NIC):`n"
        foreach ($nic in $unassignedNics) {
            $body += "  - $($nic.Name) in resource group $($nic.ResourceGroupName)`n"
        }
    }

    # Network Security Groups (NSG)
    $unassignedNSGs = Get-AzNetworkSecurityGroup | Where-Object { $_.NetworkInterfaces.Count -eq 0 -and $_.Subnets.Count -eq 0 }
    if ($unassignedNSGs) {
        $body += "`nUnassigned Network Security Groups (NSG):`n"
        foreach ($nsg in $unassignedNSGs) {
            $body += "  - $($nsg.Name) in resource group $($nsg.ResourceGroupName)`n"
        }
    }

    # Virtual Machines stopped but not deallocated
    $stoppedVMs = Get-AzVM -Status | Where-Object { 
        $_.PowerState -eq "VM stopped" -and 
        $_.Statuses.Code -contains "PowerState/stopped" 
    }
    if ($stoppedVMs) {
        $body += "`nStopped (but not deallocated) VMs (still incurring costs):`n"
        foreach ($vm in $stoppedVMs) {
            $body += "  - $($vm.Name) in resource group $($vm.ResourceGroupName)`n"
        }
    }

    # Send email if there are any unassigned resources or stopped VMs
    if ($body) {
        $body = "Company: $companyName`nSubscription: $subName ($sub)`n`nThe following Azure resources require attention:" + $body

        $subject = "$companyName - Azure: Unassigned/Stopped Resources Report ($subName)"

        Send-MailMessage -From $smtpFrom -To $smtpTo -Subject $subject `
            -Body $body -SmtpServer $smtpServer -Credential $smtpCred -UseSsl -Port $smtpPort
    } else {
        Write-Output "[$subName] No issues found."
    }
}
