################################################## Starter Function ###################################################

function Check-TagsAndAssignBackupPolicy {
  param(
    [Parameter(Mandatory = $false)]
    [string[]]$IncludedSubscriptionIds = @()
  )

  # Get all subscriptions excluding the ones provided in the excluded list
  $Subscriptions = Get-AzSubscription | Where-Object { $IncludedSubscriptionIds -contains $_.Id }

  # Create an empty array to store the VM information
  $VmInfoArray = @()

  # Loop through each subscription
  foreach ($Subscription in $Subscriptions) {

    # Import Module
    Import-Module -Name ./modules/*.psm1 -Force

    # Select the subscription
    Set-AzContext -Subscription $Subscription.Id | Out-Null

    # Get all VMs in the subscription
    $Vms = Get-AzVM

    # Loop through each VM
    foreach ($Vm in $Vms) {

      # Create a custom object for the VM
      $VmInfo = New-Object PSObject
      $VmInfo | Add-Member -MemberType NoteProperty -Name "VmName" -Value $Vm.Name
      $VmInfo | Add-Member -MemberType NoteProperty -Name "BackupPolicy" -Value $null
      $VmInfo | Add-Member -MemberType NoteProperty -Name "IsProtected" -Value $false
      $VmInfo | Add-Member -MemberType NoteProperty -Name "RecoveryServicesVault" -Value $null
      $VmInfo | Add-Member -MemberType NoteProperty -Name "Subscription" -Value $Subscription.Name

      # Get the VM location
      $VmLocation = $Vm.Location

      # Check if the "RecoveryServicesVault" and "BackupPolicy" tags are defined on the VM
      if ($Vm.Tags.RecoveryServicesVault -and $Vm.Tags.BackupPolicy) {

        # Get the name of the Recovery Services Vault and the backup policy from the VM tags
        $RecoveryServicesVaultName = $Vm.Tags.RecoveryServicesVault
        $BackupPolicyName = $Vm.Tags.BackupPolicy

        # Get the Recovery Services Vault with the given name
        $VaultAndPolicies = Get-RecoveryServicesVaultAndBackupPolicies -VaultName $RecoveryServicesVaultName -ErrorAction SilentlyContinue

        # Continue if the Vault or Policies are not found
        if ($null -eq $VaultAndPolicies.RecoveryServicesVault -or $null -eq $VaultAndPolicies.BackupPolicies) {
          Write-CustomMessage -Message "Either Recovery Services Vault or Backup policies were not found for '$RecoveryServicesVaultName'" -Type Error
          continue
        }

        # Check if the Recovery Services Vault is in the same location as the VM
        if ($VaultAndPolicies.RecoveryServicesVault.Location -ne $VmLocation) {
          Write-CustomMessage -Message "Recovery Services Vault '$RecoveryServicesVaultName' is not in the same location as VM '$($Vm.Name)'" -Type Error
          continue
        }

        # Update the Recovery Services Vault in the VM info object
        $VmInfo.RecoveryServicesVault = $VaultAndPolicies.RecoveryServicesVault.Name

        # Get the backup policy with the given name in the Recovery Services Vault
        $Policy = $VaultAndPolicies.BackupPolicies | Where-Object { $_.Name -eq $BackupPolicyName }
        $BackupPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Vault $VaultAndPolicies.RecoveryServicesVault.Id -Name $Policy.Name -ErrorAction SilentlyContinue

        # Continue if the Backup Policy is not found
        if ($null -eq $BackupPolicy) {
          Write-CustomMessage -Message "Backup policy '$BackupPolicyName' not found in Recovery Services Vault '$RecoveryServicesVaultName'" -Type Error
          continue
        }

        # Update the Backup Policy in the VM info object
        $VmInfo.BackupPolicy = $BackupPolicy.Name

        # Get the existing backup policy
        $VaultId = $VaultAndPolicies.RecoveryServicesVault.Id.ToString()
        $Container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -FriendlyName $Vm.Name -VaultId $VaultId
        $ExistingBackupPolicy = Get-AzRecoveryServicesBackupItem -WorkloadType AzureVM -Container $Container -VaultId $VaultId | Select-Object ProtectionPolicyName, PolicyId

        # Check if the VM is already being backed up
        if ($null -ne $ExistingBackupPolicy.ProtectionPolicyName) {
          Write-CustomMessage -Message "The VM '$($Vm.Name)' in Subscription: '$($Subscription.Name)' is already being backed up by policy '$($ExistingBackupPolicy.ProtectionPolicyName)'" -Type Information

          # Update the backup policy and protection status in the VM info object
          $VmInfo.BackupPolicy = $ExistingBackupPolicy.ProtectionPolicyName
          $VmInfo.IsProtected = $true
        }

        # Try to assign the backup policy to the VM
        $BackupAssignmentResult = Enable-AzRecoveryServicesBackupProtection -Policy $BackupPolicy -ErrorAction SilentlyContinue -Name $Vm.Name -ResourceGroupName $Vm.ResourceGroupName -VaultId $VaultId

        # If the assignment failed, try to assign the "EnhancedPolicy"
        if ($null -eq $BackupAssignmentResult) {
          Write-CustomMessage -Message "Failed to assign backup policy '$BackupPolicyName' to VM '$($Vm.Name)', trying EnhancedPolicy..." -Type Warning
  
          $EnhancedPolicy = $VaultAndPolicies.BackupPolicies | Where-Object { $_.Name -eq "EnhancedPolicy" }

          if ($null -eq $EnhancedPolicy) {
            Write-CustomMessage -Message "EnhancedPolicy not found in Recovery Services Vault '$RecoveryServicesVaultName', skipping ...." -Type Error
            continue
          }

          $EnhancedPolicyAssignmentResult = Enable-AzRecoveryServicesBackupProtection -Policy $EnhancedPolicy -ErrorAction SilentlyContinue -Name $Vm.Name -ResourceGroupName $Vm.ResourceGroupName -VaultId $VaultId

          if ($null -ne $EnhancedPolicyAssignmentResult) {
            $Vm.Tags.BackupPolicy = "EnhancedPolicy"
            Update-AzTag -ResourceId $Vm.Id -Tag $Vm.Tags -Operation Merge -ErrorAction SilentlyContinue | Out-Null
            Write-CustomMessage -Message "Assigned EnhancedPolicy to VM '$($Vm.Name)'" -Type Information

            # Update the backup policy and protection status in the VM info object
            $VmInfo.BackupPolicy = "EnhancedPolicy"
            $VmInfo.IsProtected = $true
          }
        }
        else {
          # Log success message
          Write-CustomMessage -Message "Assigned backup policy '$BackupPolicyName' to VM '$($Vm.Name)'" -Type Information

          # Update the backup policy and protection status in the VM info object
          $VmInfo.BackupPolicy = $BackupPolicyName
          $VmInfo.IsProtected = $true
        }
      }

      # Add the VM info object to the array
      $VmInfoArray += $VmInfo
    }
  }

  # Output the VM info array as a table
  $VmInfoArray | Format-Table -AutoSize
}

################################################## Call Function ###################################################

Check-TagsAndAssignBackupPolicy -$IncludedSubscriptionIds@("")