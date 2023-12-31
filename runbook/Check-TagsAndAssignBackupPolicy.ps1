<#
.SYNOPSIS
Checks the tags of Azure virtual machines and assigns a backup policy based on the tags.

.DESCRIPTION
This script checks the tags of Azure virtual machines in the specified subscriptions and assigns a backup policy based on the tags. If a virtual machine has a tag named "BackupPolicy" with a value that matches the name of a backup policy in the specified Recovery Services Vault, the script assigns that backup policy to the virtual machine. If no matching backup policy is found, the script assigns the "EnhancedPolicy" backup policy to the virtual machine.

.PARAMETER IncludedSubscriptionIds
An array of subscription IDs to include in the backup policy assignment. If not specified, the script will include all subscriptions that the authenticated user has access to.

.PARAMETER All
If specified, the script will include all subscriptions that the authenticated user has access to.

.EXAMPLE
Check-TagsAndAssignBackupPolicy.ps1 -IncludedSubscriptionIds "12345678-1234-1234-1234-123456789012", "23456789-2345-2345-2345-234567890123"

This example runs the script and includes only the specified subscriptions in the backup policy assignment.

.NOTES
This script requires the Azure PowerShell module to be installed and authenticated with a service principal that has the necessary permissions to manage virtual machines and backup policies in the specified subscriptions and Recovery Services Vault.
#>

param (
  [Parameter(Mandatory = $false)]
  [array]$IncludedSubscriptionIds,

  [Parameter(Mandatory = $false)]
  [switch]$All
)

################################################## Starter Function ###################################################
function Check-TagsAndAssignBackupPolicy {
  param(
    [Parameter(Mandatory = $false)]
    [string[]]$IncludedSubscriptionIds,

    [Parameter(Mandatory = $false)]
    [switch]$All
  )
  Begin {

    if ($PSBoundParameters.ContainsKey('All') -and $PSBoundParameters.ContainsKey('IncludedSubscriptionIds')) {
      Write-CustomMessage -Message "The -All and -IncludedSubscriptionIds parameters cannot be used together!" -Type Error
      return
    }
    elseif ($PSBoundParameters.ContainsKey('All')) {
      $Subscriptions = Get-AzSubscription
    }
    else {
      $Subscriptions = $IncludedSubscriptionIds | ForEach-Object { Get-AzSubscription -SubscriptionId $_ }
    }
  }

  Process {

    # Create an empty array to store the VM information
    $VmInfoArray = [System.Collections.ArrayList]::new()

    # Loop through each subscription
    foreach ($Subscription in $Subscriptions) {

      # Get all VMs in the subscription
      $Vms = Get-AzVM

      # Loop through each VM
      foreach ($Vm in $Vms) {

        # Check if the VM is already being backed up
        $currentBackupStatus = Get-AzRecoveryServicesBackupStatus -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Type 'AzureVM' -ErrorAction SilentlyContinue

        # Check if the "RecoveryServicesVault" and "BackupPolicy" tags are defined on the VM
        if ($Vm.Tags.RecoveryServicesVault -and $Vm.Tags.BackupPolicy) {

          # if trusted launch is enabled, set switch -EnhancedPolicy to $true
          $PolicyName = $vm.SecurityProfile.SecurityType -eq "TrustedLaunch" ? 'EnhancedPolicy' : $Vm.Tags.BackupPolicy 

          $RecoveryServicesVault = Get-AzRecoveryServicesVault -Name $Vm.Tags.RecoveryServicesVault

          if ($RecoveryServicesVault) {

            # Get the backup policies in the Recovery Services Vault
            $BackupPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Vault $RecoveryServicesVault.Id -Name $PolicyName

          }
          if (-not $PolicyAssignmentFailure -and $currentBackupStatus.BackedUp -eq $false -and $BackupPolicy -ne $null) {
            try {

              # Set Vault context
              Set-AzRecoveryServicesVaultContext -Vault $RecoveryServicesVault
              # Enable backup protection
              $AssignmentStatus = Enable-AzRecoveryServicesBackupProtection -Policy $BackupPolicy -Name $Vm.Name -ResourceGroupName $Vm.ResourceGroupName

              Write-Host $AssignmentStatus

              # If successful, set PolicyAssignmentSuccessful to $true
              if ($AssignmentStatus.Status -eq 'Succeeded') {
                $Status = $true
              }
            }
            catch {
              $PolicyAssignmentFailure = $_.Exception.Message
            }
          }
        }

        [void]$VmInfoArray.Add([PSCustomObject]@{
            VmName                             = $Vm.Name
            VmLocation                         = $Vm.Location
            AlreadyBackedUp                    = $currentBackupStatus.BackedUp
            PolicyAssignmentSuccessful         = $currentBackupStatus.BackedUp ? $false : $Status
            BackupPolicy                       = $null -ne $Policy.Name ? $Policy.Name : $vm.Tags.BackupPolicy
            TagsSet                            = $Vm.Tags.BackupPolicy -and $Vm.Tags.RecoveryServicesVault ? $true :$false
            RecoveryServicesVault              = $false -ne $RecoveryServicesVault ? $RecoveryServicesVault.Name : ($currentBackupStatus.VaultId -split "/" | Select-Object -Last 1)
            RecoveryServicesVaultLocation      = $RecoveryServicesVault.Location
            RecoveryServicesVaultLocationMatch = $RecoveryServicesVault.Location -match $Vm.Location ? $true : $false
            Subscription                       = $Subscription.Name
            ErrorMessage                       = $PolicyAssignmentFailure
          })
      }
    }
  }
  End {
    $VmInfoArray
  }
}

################################################## Call Function ###################################################
$functionParams = @{}

if ($All) {
  $functionParams['All'] = $true
}
elseif ($IncludedSubscriptionIds) {
  $functionParams['IncludedSubscriptionIds'] = $IncludedSubscriptionIds
}
else {
  throw "You must specify either the -All or -IncludedSubscriptionIds parameter!"
}

Check-TagsAndAssignBackupPolicy @functionParams


