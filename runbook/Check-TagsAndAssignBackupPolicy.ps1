<#
.SYNOPSIS
Checks the tags of Azure virtual machines and assigns a backup policy based on the tags.

.DESCRIPTION
This script checks the tags of Azure virtual machines in the specified subscriptions and assigns a backup policy based on the tags. If a virtual machine has a tag named "BackupPolicy" with a value that matches the name of a backup policy in the specified Recovery Services Vault, the script assigns that backup policy to the virtual machine. If no matching backup policy is found, the script assigns the "EnhancedPolicy" backup policy to the virtual machine.

.PARAMETER IncludedSubscriptionIds
An array of subscription IDs to include in the backup policy assignment. If not specified, the script will include all subscriptions that the authenticated user has access to.

.EXAMPLE
Check-TagsAndAssignBackupPolicy.ps1 -IncludedSubscriptionIds "12345678-1234-1234-1234-123456789012", "23456789-2345-2345-2345-234567890123"

This example runs the script and includes only the specified subscriptions in the backup policy assignment.

.NOTES
This script requires the Azure PowerShell module to be installed and authenticated with a service principal that has the necessary permissions to manage virtual machines and backup policies in the specified subscriptions and Recovery Services Vault.
#>

param (
  [Parameter(Mandatory = $true)]
  [array]$IncludedSubscriptionIds,

  [Parameter(Mandatory = $false)]
  [switch]$All
)

################################################## Starter Function ###################################################
function Check-TagsAndAssignBackupPolicy {
  param(
    [Parameter(Mandatory = $false)]
    [string[]]$IncludedSubscriptionIds = @(),

    [Parameter(Mandatory = $false)]
    [switch]$All
  )

  if ($All) {
    $IncludedSubscriptionIds = Get-AzSubscription | Select-Object -ExpandProperty Id
  }
  else {
    # Get all subscriptions excluding the ones provided in the excluded list
    $Subscriptions = Get-AzSubscription | Where-Object { $IncludedSubscriptionIds -contains $_.Id }  
  }

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

      # Check if the "RecoveryServicesVault" and "BackupPolicy" tags are defined on the VM
      if ($Vm.Tags.RecoveryServicesVault -and $Vm.Tags.BackupPolicy) {

        # Get the Recovery Services Vault with the given name
        $VaultAndPolicies = Get-RecoveryServicesVaultAndBackupPolicies -VaultName $($Vm.Tags.RecoveryServicesVault) -Location $Vm.Location -PolicyName $Vm.Tags.BackupPolicy -ErrorAction SilentlyContinue

        # Continue if the Vault or Policies are not found
        if ($VaultAndPolicies.Values -contains $false) {
          Write-CustomMessage -Message "Either Recovery Services Vault or Backup policies were not found for '$($Vm.Name)' or the location doesnt match!" -Type Error
          continue
        }
        
        # Update the Recovery Services Vault in the VM info object
        $VmInfo.RecoveryServicesVault = $VaultAndPolicies.RecoveryServicesVault.Name

        # Update the Backup Policy in the VM info object
        $VmInfo.BackupPolicy = $BackupPolicy.Name

        # Get the existing backup policy
        $VaultId = $VaultAndPolicies.RecoveryServicesVault.Id.ToString()
        $Container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -FriendlyName $Vm.Name -VaultId $VaultId

        $ExistingBackupPolicy = $Container.IsNullorEmpty ? 
          $null :
          (Get-AzRecoveryServicesBackupItem -WorkloadType AzureVM -Container $Container -VaultId $VaultId | Select-Object ProtectionPolicyName, PolicyId) 

        # Check if the VM is already being backed up
        $VmInfo.IsProtected = -not $ExistingBackupPolicy.ProtectionPolicyName.IsNullorEmpty

        $BackupAssignmentResult = Enable-AzRecoveryServicesBackupProtection -Policy $BackupPolicy -ErrorAction SilentlyContinue -Name $Vm.Name -ResourceGroupName $Vm.ResourceGroupName -VaultId $VaultId

        $VmInfo.BackupPolicy = $VmInfo.IsProtected ? 
          ($ExistingBackupPolicy.ProtectionPolicyName) : 
          ($null -ne $BackupAssignmentResult ? $BackupPolicy.Name : $null)

        if ($VmInfo.IsProtected) {
          Write-CustomMessage -Message "The VM '$($Vm.Name)' in Subscription: '$($Subscription.Name)' is already being backed up by policy '$($ExistingBackupPolicy.ProtectionPolicyName)'" -Type Information
        }

        $EnhancedPolicy = $null -eq $BackupAssignmentResult -and $Vm.Tags.BackupPolicy -eq "DefaultPolicy" ? 
          ($VaultAndPolicies.BackupPolicies | Where-Object { $_.Name -eq "EnhancedPolicy" }) : 
          $null

        $Message = $null -eq $BackupAssignmentResult -and $Vm.Tags.BackupPolicy -ne "EnhancedPolicy" ?
          ("Failed to assign backup policy '$($Vm.Tags.BackupPolicy)' to VM '$($Vm.Name)', trying EnhancedPolicy...") : 
          ("Assigned backup policy '$($Vm.Tags.BackupPolicy)' to VM '$($Vm.Name)'")

        Write-CustomMessage -Message $Message -Type ($null -eq $BackupAssignmentResult ? 'Warning' : 'Information')

        if ($null -eq $BackupAssignmentResult -and $null -ne $EnhancedPolicy) {
          $EnhancedPolicyAssignmentResult = Enable-AzRecoveryServicesBackupProtection -Policy $EnhancedPolicy -ErrorAction SilentlyContinue -Name $Vm.Name -ResourceGroupName $Vm.ResourceGroupName -VaultId $VaultId
          $Vm.Tags.BackupPolicy = $null -ne $EnhancedPolicyAssignmentResult ? "EnhancedPolicy" : $Vm.Tags.BackupPolicy
          $VmInfo.BackupPolicy = $Vm.Tags.BackupPolicy
          $VmInfo.IsProtected = $null -ne $EnhancedPolicyAssignmentResult
          Write-CustomMessage -Message ($VmInfo.IsProtected ? "Assigned EnhancedPolicy to VM '$($Vm.Name)'" : "EnhancedPolicy not found in Recovery Services Vault '$($Vm.Tags.RecoveryServicesVault)', skipping ....") -Type ($VmInfo.IsProtected ? 'Information' : 'Error')
          if ($VmInfo.IsProtected) {
            Update-AzTag -ResourceId $Vm.Id -Tag $Vm.Tags -Operation Merge -ErrorAction SilentlyContinue | Out-Null
          }
        }
        else {
          $VmInfo.BackupPolicy = $Vm.Tags.BackupPolicy
          $VmInfo.IsProtected = $true
        }
      }       
      else {
        Write-CustomMessage -Message "Either RecoveryServicesVault or BackupPolicy tags are not defined on VM '$($Vm.Name)'" -Type Warning
      }

      # Add the VM info object to the array
      $VmInfoArray += $VmInfo

      # Output the VM info array as a table
      $VmInfoArray | Format-Table -AutoSize
    }
  }
}

################################################## Call Function ###################################################
Check-TagsAndAssignBackupPolicy -IncludedSubscriptionIds $IncludedSubscriptionIds

