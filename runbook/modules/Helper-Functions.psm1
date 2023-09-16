################################################## Helper Functions ##################################################

function Get-RecoveryServicesVaultAndBackupPolicies {
  <#
    .SYNOPSIS
      Retrieves a specified Recovery Services Vault and its Backup Policies based on the given parameters.

    .PARAMETER VaultName
      The name of the Recovery Services Vault to retrieve.

    .PARAMETER Location
      The location to match with the Recovery Services Vault's location.

    .PARAMETER PolicyName
      The name of the backup policy to retrieve.
  #>
  param(
    [Parameter(Mandatory = $true)]
    [string]$VaultName,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $true)]
    [string]$PolicyName,

    [Parameter(Mandatory = $false)]
    [bool]$EnhancedPolicy
  )

  # Get the Recovery Services Vault
  $RecoveryServicesVault = Get-AzRecoveryServicesVault -Name $VaultName

  if ($RecoveryServicesVault) {

    $PolicyName = $EnhancedPolicy -eq $true ? 'EnhancedPolicy' : $PolicyName
    
    # Get the backup policies in the Recovery Services Vault
    $BackupPolicies = Get-AzRecoveryServicesBackupProtectionPolicy -Vault $RecoveryServicesVault.Id

    # Get the backup policy with the given name
    $Policy = $BackupPolicies | Where-Object { $_.Name -eq $PolicyName }

    # Check if the Location of the Vault matches the given Location of the VM
    $RecoveryServicesVaultLocationMatch = $Location -match $RecoveryServicesVault.Location ? $true : $false

    if ($Policy.Name -or $RecoveryServicesVaultLocationMatch) {

      $policyBase = New-Object 'Microsoft.Azure.Commands.RecoveryServices.Backup.Cmdlets.Models.PolicyBase'
      $policyBase | Add-Member -MemberType NoteProperty -Name $Policy.Name -Value $Policy

      return @{
        RecoveryServicesVault             = $RecoveryServicesVault
        RecoveryServicesVaultLocation     = $RecoveryServicesVault.Location
        AllBackupPolicies                 = $BackupPolicies.Name
        RecoveryServiceVaultLocationMatch = $RecoveryServicesVaultLocationMatch
        Policy                            = $null -ne $Policy ? $policyBase : $false
        PolicyName                        = $Policy.Name
      }
    }
  }
  else {
    return $false
  }
}

function Write-CustomMessage {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Error', 'Warning', 'Information', 'Verbose', 'Debug')]
    [string]$Type = 'Error'
  )

  # Use a hashtable to map types to their corresponding cmdlets 
  $typeCmdletMap = @{
    'Error'       = { param($msg) Write-Host $msg -ForegroundColor Red }
    'Warning'     = { param($msg) Write-Host $msg -ForegroundColor Yellow }
    'Information' = { param($msg) Write-Host $msg -ForegroundColor Green }
    'Verbose'     = { param($msg) Write-Verbose $msg }
    'Debug'       = { param($msg) Write-Debug $msg }
  }

  # Invoke the cmdlet from the hashtable with the message as a parameter
  & $typeCmdletMap[$Type] $Message
}
