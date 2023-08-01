function Get-RecoveryServicesVaultAndBackupPolicies {
  param(
    [Parameter(Mandatory = $true)]
    [string]$VaultName
  )

  # Get the Recovery Services Vault
  $RecoveryServicesVault = Get-AzRecoveryServicesVault -Name $VaultName

  if ($RecoveryServicesVault -eq $null) {
    return @{
      RecoveryServicesVault = $null
      BackupPolicies        = $null
    }
  }
  else {
    # Get the backup policies in the Recovery Services Vault
    $BackupPolicies = Get-AzRecoveryServicesBackupProtectionPolicy -Vault $RecoveryServicesVault.Id | Select-Object -Property Name, Id

    return @{
      RecoveryServicesVault = $RecoveryServicesVault
      BackupPolicies        = $BackupPolicies
    }
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
    'Error'       = { param($msg) $ErrorRecord = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList (
        [System.Exception]::new($msg),
        'Error',
        'NotSpecified',
        $null
      )
      $ErrorRecord | Write-Error }
    'Warning'     = { param($msg) $msg | Write-Warning }
    'Information' = { param($msg) $msg | Write-Information }
    'Verbose'     = { param($msg) $msg | Write-Verbose }
    'Debug'       = { param($msg) $msg | Write-Debug }
  }

  # Invoke the cmdlet from the hashtable with the message as a parameter
  & $typeCmdletMap[$Type] $Message
}


