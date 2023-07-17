function Check-TagsAndAssignBackupPolicy {
    param(
        [string]$LawWorkspaceName,
        [string]$LawResourceGroup
    )

    # Get all subscriptions
    $Subscriptions = Get-AzSubscription

    # Loop through each subscription
    foreach ($Subscription in $Subscriptions) {
        Set-AzContext -Subscription $Subscription.Id | Out-Null

        # Get all VMs in the subscription
        $Vms = Get-AzVM

        # Loop through each VM
        foreach ($Vm in $Vms) {

            # Get the VM location
            $VmLocation = $Vm.Location

            # Check if the "RecoveryServicesVault" and "BackupPolicy" tags are defined on the VM
            if ($Vm.Tags.RecoveryServicesVault -and $Vm.Tags.BackupPolicy) {

                # Get the name of the Recovery Services Vault and the backup policy from the VM tags
                $RecoveryServicesVaultName = $Vm.Tags.RecoveryServicesVault
                $BackupPolicyName = $Vm.Tags.BackupPolicy

                # Get the Recovery Services Vault with the given name in the VM location
                try {
                    $VaultAndPolicies = Get-RecoveryServicesVaultAndBackupPolicies -ResourceGroupName $LawResourceGroup -VaultName $RecoveryServicesVaultName -ErrorAction Stop
                }
                catch {
                    $ErrorMessage = "Failed to get Recovery Services Vault and backup policies: $($_.Exception.Message)"
                    Write-Error $ErrorMessage
                    Write-LogAnalytics -WorkspaceId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsSharedKey -LawWorkspaceName $LawWorkspaceName -LawResourcegroup $LawResourceGroup -ErrorMessage $ErrorMessage
                    continue
                }

                $RecoveryServicesVault = $VaultAndPolicies.RecoveryServicesVault
                $BackupPolicies = $VaultAndPolicies.BackupPolicies

                # Check if the Recovery Services Vault was found
                if ($RecoveryServicesVault -eq $null) {
                    $ErrorMessage = "Recovery Services Vault '$RecoveryServicesVaultName' not found in location '$VmLocation'"
                    Write-Error $ErrorMessage
                    Write-LogAnalytics -WorkspaceId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsSharedKey -LawWorkspaceName $LawWorkspaceName -LawResourcegroup $LawResourceGroup -ErrorMessage $ErrorMessage
                    continue
                }

                # Get the backup policy with the given name in the Recovery Services Vault
                try {
                    $Policy = $BackupPolicies | Where-Object { $_.Name -eq $BackupPolicyName }
                    $BackupPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Vault $RecoveryServicesVault.Id -Name $Policy.Name -ErrorAction Stop
                }
                catch {
                    $ErrorMessage = "Failed to get backup policy: $($_.Exception.Message)"
                    Write-Error $ErrorMessage
                    Write-LogAnalytics -WorkspaceId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsSharedKey -LawWorkspaceName $LawWorkspaceName -LawResourcegroup $LawResourceGroup -ErrorMessage $ErrorMessage
                    continue
                }

                # Check if the backup policy was found
                if ($BackupPolicy -eq $null) {
                    $ErrorMessage = "Backup policy '$BackupPolicyName' not found in Recovery Services Vault '$RecoveryServicesVaultName'"
                    Write-Error $ErrorMessage
                    Write-LogAnalytics -WorkspaceId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsSharedKey -LawWorkspaceName $LawWorkspaceName -LawResourcegroup $LawResourceGroup -ErrorMessage $ErrorMessage
                    continue
                }

                # Get the existing backup policy
                $Container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -FriendlyName $Vm.Name -VaultId $RecoveryServicesVault.Id
                $ExistingBackupPolicy = Get-AzRecoveryServicesBackupItem -WorkloadType AzureVM -Container $Container -VaultId $RecoveryServicesVault.Id | Select-Object ProtectionPolicyName, PolicyId

                # Check if the existing backup policy differs from the policy defined in the VM tags
                if ($ExistingBackupPolicy.PolicyId -ne $BackupPolicy.Id) {
                    $DifferenceMessage = "The backup policy assigned to VM '$($Vm.Name)' differs from the one defined in the VM tags: '$($ExistingBackupPolicy.Name)' vs '$BackupPolicyName'"
                    Write-Warning $DifferenceMessage
                    Write-LogAnalytics -WorkspaceId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsSharedKey -DifferenceMessage $DifferenceMessage
                }
                # Assign the backup policy to the VM
                try {
                    Enable-AzRecoveryServicesBackupProtection -Policy $BackupPolicy -ErrorAction Stop -Name $Vm.Name -ResourceGroupName $Vm.ResourceGroupName -VaultId $RecoveryServicesVault.Id
                }
                catch {
                    $ErrorMessage = "Failed to assign backup policy '$BackupPolicyName' to VM '$($Vm.Name)': $($_.Exception.Message)"
                    Write-Error $ErrorMessage
                    Write-LogAnalytics -WorkspaceId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsSharedKey -LawWorkspaceName $LawWorkspaceName -LawResourcegroup $LawResourceGroup -ErrorMessage $ErrorMessage
                    continue
                }

                # Log success message
                $SuccessMessage = "Assigned backup policy '$BackupPolicyName' to VM '$($Vm.Name)'"
                Write-Host $SuccessMessage
            }
        }
    }
}

function Get-RecoveryServicesVaultAndBackupPolicies {
    param(
        [string]$ResourceGroupName,
        [string]$VaultName
    )

    $RecoveryServicesVault = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName -Name $VaultName

    $BackupPolicies = Get-AzRecoveryServicesBackupProtectionPolicy -Vault $RecoveryServicesVault.Id | Select-Object -Property Name, Id

    return @{
        RecoveryServicesVault = $RecoveryServicesVault
        BackupPolicies        = $BackupPolicies
    }
}

function Write-LogAnalytics {
    param (
        [string]$LawWorkspaceName,
        [string]$LawResourcegroup,
        [string]$ErrorMessage,
        [string]$DifferenceMessage,
        [string]$SuccessMessage
    )
    # Check if the Azure PowerShell module is installed
    if ((Get-Module -Name Az -ListAvailable) -eq $null) {
        Write-Warning "Azure PowerShell module not installed. Cannot log to Log Analytics."
        return
    }

    # Create the Log Analytics record
    $Record = @{ 
        TimeGenerated     = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        ErrorMessage      = $ErrorMessage 
        DifferenceMessage = $DifferenceMessage
        SuccessMessage    = $SuccessMessage
    }

    # Convert the record to JSON
    $RecordJson = ConvertTo-Json $Record

    # Send the Log Analytics record
    try {
        $LogAnalyticsCustomerId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $LawResourcegroup -Name $LawWorkspaceName).CustomerId
        $LogAnalyticsSharedKey = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $LawResourcegroup -Name $LawWorkspaceName).PrimarySharedKey
        $LogType = "CustomLog"
        $jsonBody = [System.Text.Encoding]::UTF8.GetBytes($RecordJson)
        $date = [System.DateTime]::UtcNow.ToString("r")
        $signature = Build-Signature -customerId $LogAnalyticsCustomerId -sharedKey $LogAnalyticsSharedKey -date $date -contentLength $jsonBody.Length -method "POST" -contentType "application/json" -resource "/api/logs"
        $uri = "https://" + $LogAnalyticsCustomerId + ".ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
        $headers = @{
            "Authorization"        = $signature
            "Log-Type"             = $LogType
            "x-ms-date"            = $date
            "time-generated-field" = "TimeGenerated"
        }
        $response = Invoke-RestMethod -Uri $uri -Method 'Post' -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($RecordJson))
        return $response.StatusCode
    }
    catch {
        Write-Warning "Failed to log to Log Analytics: $($_.Exception.Message)"
        return
    }
}

function Build-Signature {
    param(
        [string]$customerId,
        [string]$sharedKey,
        [string]$date,
        [int]$contentLength,
        [string]$method,
        [string]$contentType,
        [string]$resource
    )

    $xHeaders = "x-ms-date:$date"
    $stringToHash = "$method`n$contentLength`n$contentType`n$xHeaders`n$resource"
    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)
    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId, $encodedHash
    return $authorization
}

function Search-LogAnalyticsWorkspace {
    param(
        [string]$WorkspaceName,
        [string]$ResourceGroup,
        [string]$CurrentSubscriptionName
    )

    # Iterate over all subscriptions
    $Subscriptions = Get-AzSubscription

    foreach ($Subscription in $Subscriptions) {
        # Check if the subscription is the current subscription
        if ($Subscription.Name -eq $CurrentSubscriptionName) {
            # Select the current subscription
            Select-AzSubscription -SubscriptionId $Subscription.Id
        }
        else {
            # Skip the subscription
            continue
        }

        # Check if the Log Analytics workspace exists
        $LogAnalyticsWorkspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroup -Name $WorkspaceName -ErrorAction SilentlyContinue

        if ($LogAnalyticsWorkspace -ne $null) {
            # Return the Log Analytics workspace
            return $LogAnalyticsWorkspace
        }
    }
}