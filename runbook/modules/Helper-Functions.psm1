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
    [string]$PolicyName
  )

  # Get the Recovery Services Vault
  $RecoveryServicesVault = Get-AzRecoveryServicesVault -Name $VaultName
  if (-not $RecoveryServicesVault) {
    return @{
      RecoveryServicesVault = $false
      BackupPolicies        = $false
      LocationMatch         = $false
      Policy                = $false
    }
  }

  # Get the backup policies in the Recovery Services Vault
  $BackupPolicies = Get-AzRecoveryServicesBackupProtectionPolicy -Vault $RecoveryServicesVault.Id

  # Get the backup policy with the given name
  $Policy = $BackupPolicies | Where-Object { $_.Name -eq $PolicyName }

  return @{
    RecoveryServicesVault = $RecoveryServicesVault
    BackupPolicies        = $BackupPolicies
    LocationMatch         = $RecoveryServicesVault.Location -eq $Location ? $true : $false
    Policy                = $Policy -ne $null ? $Policy : $false
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
