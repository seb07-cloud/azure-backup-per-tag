<#
.SYNOPSIS
    Assigns a backup policy to a VM based on the tags of the VM
.DESCRIPTION
    Assigns and replaces a backup policy to a VM based on the tags of the VM
.NOTES
    Author:            Sebastian Wild
    Company:           Axians ICT Austria
	Date : 			   08.02.2023
       
    Changelog:
	1.0                Initial Release
.LINK
    nothing yet

.PARAMETER
    $keyvaultname                   --> The name of the KeyVault
    $keyvaultsecretname             --> The Displayname of the secret

.EXAMPLE
    add-azbackuppolicy 

.OUTPUTS
    Nothing yet
#>


function Get-AxAzVMBackupStatus {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AzureVMName,
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true)]
        [string]$BackupPolicyName,
        [Parameter(Mandatory = $true)]
        [string]$RecoveryServicesVaultName

    )
    
    try {

        $RecoveryVaultInfo = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName -Name $BackupPolicyName -Type 'AzureVM'
        $BackupVaults = Get-AzRecoveryServicesVault -Name $RecoveryServicesVaultName

        if ($RecoveryVaultInfo.BackedUp -eq $true) {

            Write-Host "$($AzureVMName) - BackedUp : Yes" -ForegroundColor Green
            $VmBackupVault = $BackupVaults | Where-Object { $_.ID -eq $RecoveryVaultInfo.VaultId } 

            #Backup recovery Vault policy Information
            $container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -VaultId $VmBackupVault.ID -FriendlyName $AzureVMName
            $backupItem = Get-AzRecoveryServicesBackupItem -Container $container -WorkloadType AzureVM -VaultId $VmBackupVault.ID


            #### TODO: Check if Policy from Tag and Policy from VM are the same
            #Backup Policy Information
            Write-Host "Backup Policy Old: $($backupItem.ProtectionPolicyName)"
            Write-Host "Backup Policy New: $($BackupPolicyName)"
            if ($BackupPolicyName -eq $backupItem.ProtectionPolicyName) {
                Write-Host "$($AzureVMName) - Backup Policy : $($BackupPolicyName)" -ForegroundColor Green

                return New-Object -TypeName PSObject -Property @{

                    RecoveryServicesVaultId   = $VmBackupVault.ID
                    RecoveryServicesVaultName = $VmBackupVault.Name
                    BackedUp                  = $true
                    NewPolicy                 = $true
                }
            }
            else {
                return New-Object -TypeName PSObject -Property @{

                    RecoveryServicesVaultId   = $VmBackupVault.ID
                    RecoveryServicesVaultName = $VmBackupVault.Name
                    BackedUp                  = $true
                    NewPolicy                 = $false
                }
            }
        }
        else {
            Write-Host "$($AzureVMName) - BackedUp : No" -ForegroundColor Red
            return New-Object -TypeName PSObject -Property @{

                RecoveryServicesVaultId   = $VmBackupVault.ID
                RecoveryServicesVaultName = $VmBackupVault.Name
                BackedUp                  = $false
                NewPolicy                 = $false
            }
        }
        
    }
    catch {
        return $false
    }
}

function Get-AxAzBackupPolicy {
    param (
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    try {
        $RecoveryvaultId = (Get-AzRecoveryServicesVault -Name $InputObject.RecoveryServicesVault).ID

        # get recovery vault
        if ($RecoveryvaultId) {

            # Write-Host "Fetched Recovery Services Vault ID: $RecoveryvaultId for querying $($InputObject.BackupPolicyName)" -ForegroundColor Green

            # set Backup Vault Context
            Get-AzRecoveryServicesVault -Name $InputObject.RecoveryServicesVault | Set-AzRecoveryServicesVaultContext
            
            $policy = Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $RecoveryvaultId -Name $InputObject.BackupPolicyName
            # Write-Host "Fetched Backup Policy: $policy." -ForegroundColor Green

            # get backup policy
            if ($null -ne $policy) {
                # Write-Host "Backup Policy $InputObject.BackupPolicy found." -ForegroundColor Green
                return New-Object -TypeName PSObject -Property @{
                    RecoveryServicesVaultId = $RecoveryvaultId
                }
            }
        }
        else { $null }
    }
    catch {
        return $null
    }
}

function Enable-AxAzBackupPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AzureVMName,
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true)]
        [string]$RecoveryServicesVaultName,
        [Parameter(Mandatory = $true)]
        [string]$RecoveryServicesVaultId,
        [Parameter(Mandatory = $true)]
        [string]$BackupPolicyName, 
        [Parameter(Mandatory = $false)]
        [bool]$ReplacePolicy = $false,
        [Parameter(Mandatory = $false)]
        [bool]$RemoveRecoveryPoints = $false
    )

    $status = Get-AxAzVMBackupStatus -AzureVMName $AzureVMName `
        -ResourceGroupName $ResourceGroupName `
        -RecoveryServicesVaultName $RecoveryServicesVaultName `
        -BackupPolicyName $BackupPolicyName

    if ((($status.BackedUp -eq $true) -and ($status.NewPolicy -eq $true) -and $ReplacePolicy)) {
        try {
            Write-Host "Removing existing backup policy for VM $AzureVMName and enabling new policy $BackupPolicyName`n" -ForegroundColor Yellow
            $Pol = Get-AzRecoveryServicesBackupProtectionPolicy -Name $BackupPolicyName

            $Container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -FriendlyName $AzureVMName -VaultId $RecoveryServicesVaultId
            $BackupItem = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM -VaultId $RecoveryServicesVaultId -Name $AzureVMName

            if ($RemoveRecoveryPoints) {

                if ($BackupItem) {
                    Write-Host "Removing soft-deleted BackupItems for VM $AzureVMName`n" -ForegroundColor Yellow
                    Undo-AzRecoveryServicesBackupItemDeletion -Item $BackupItem -VaultId $RecoveryServicesVaultId -Force
                    Disable-AzRecoveryServicesBackupProtection -Item $BackupItem -RemoveRecoveryPoints -VaultId $RecoveryServicesVaultId -Force
                }
                else {
                    Write-Host "No soft-deleted Backups, proceeding ... $AzureVMName`n" -ForegroundColor Yellow
                    Disable-AzRecoveryServicesBackupProtection -VaultId $RecoveryServicesVaultId -Force -RemoveRecoveryPoints 

                }
            }
            else {
                Write-Host "Keeping recovery points for VM $AzureVMName`n" -ForegroundColor Yellow
                Disable-AzRecoveryServicesBackupProtection -Item $BackupItem -VaultId $RecoveryServicesVaultId -Force
            }

            Enable-AzRecoveryServicesBackupProtection -ResourceGroupName $ResourceGroupName -Name $AzureVMName -Policy $Pol -VaultId $RecoveryServicesVaultId
            
        }
        catch {
            Write-Host $_.Exception.Message
        }
    }
    else {
        try {
            Write-Host "VMName:$($AzureVMName) - BackupPolicy: $($BackupPolicyName) - Enabling: Yes" -ForegroundColor Green
            $Pol = Get-AzRecoveryServicesBackupProtectionPolicy -Name $BackupPolicyName
            Enable-AzRecoveryServicesBackupProtection -ResourceGroupName $ResourceGroupName -Name $AzureVMName -Policy $Pol -VaultId $RecoveryServicesVaultId
        }
        catch {
            Write-Host $_.Exception.Message
        }
    }
}

function Get-AxAzBackupTags {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AzureVMName,
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )

    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $AzureVMName
    $tag = $vm.Tags

    if ($tag.ContainsKey("BackupPolicy") -and $tag.ContainsKey("RecoveryServicesVault")) {
        return New-Object -TypeName PSObject -Property @{
            BackupPolicyName      = $tag["BackupPolicy"]
            RecoveryServicesVault = $tag["RecoveryServicesVault"]
        }
    }
    else {
        return $false
    }
}

function Set-AxAzBackupPolicy {

    param(
        [Parameter(Mandatory = $false)]
        [bool]$ReplacePolicy = $false,
        [Parameter(Mandatory = $false)]
        [bool]$RemoveRecoveryPoints = $false
    )

    if (Get-AzContext) {
        Write-Host "Logged in to Azure" -ForegroundColor Green

        $subscriptionlist = Get-AzSubscription | Select-Object -ExpandProperty id (Get-AzSubscription).Name

        foreach ($subscription in $subscriptionlist) {
    
            Select-AzSubscription -SubscriptionId $Subscription | Out-Null

            foreach ($vm in (Get-AzVM)) {

                Write-Host "`nChecking VM $($vm.Name) in Resource Group $($vm.ResourceGroupName)`n" -ForegroundColor DarkCyan

                if ((($tags = Get-AxAzBackupTags -AzureVMName $vm.Name -ResourceGroupName $vm.ResourceGroupName)) -ne $false) {

                    $recovery = Get-AxAzBackupPolicy $tags

                    if ($recovery) {

                        Write-Host "VM:                         $($vm.Name)" -ForegroundColor Green
                        Write-Host "Resource Group:             $($vm.ResourceGroupName)" -ForegroundColor Green
                        Write-Host "Recovery Services Vault:    $($tags.RecoveryServicesVault)" -ForegroundColor Green
                        Write-Host "Backup policy:              $($tags.BackupPolicyName)" -ForegroundColor Green
                        Write-Host "Replace policy:             $($ReplacePolicy)`n" -ForegroundColor Green

                        Enable-AxAzBackupPolicy -AzureVMName $vm.Name `
                            -ResourceGroupName $vm.ResourceGroupName `
                            -RecoveryServicesVaultName $tags.RecoveryServicesVault `
                            -RecoveryServicesVaultId $recovery.RecoveryServicesVaultId `
                            -BackupPolicyName $tags.BackupPolicyName `
                            -ReplacePolicy $ReplacePolicy `
                            -RemoveRecoveryPoints $RemoveRecoveryPoints
                    }
                }
                else { Write-Host "No backup policy found for VM $($vm.Name) in Resource Group $($vm.ResourceGroupName)`n" -ForegroundColor Yellow }
            }
        }
    }
    else {
        Write-Host "Not logged in to Azure, please login first" -ForegroundColor Red
        return
    }
}

Export-ModuleMember -Function Set-AxAzBackupPolicy


