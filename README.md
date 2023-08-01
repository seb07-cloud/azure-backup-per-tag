# Check Tags and Assign Backup Policy

This PowerShell script, `Check-TagsAndAssignBackupPolicy`, is designed to automate the process of managing Azure VM backup policies across multiple subscriptions. It checks for specific tags on VMs and assigns backup policies accordingly, ensuring that VMs are protected and compliant with desired backup configurations.

## Features

- **Multi-Subscription Support:** The script scans all subscriptions, excluding any specified in the exclusion list.
- **Tag-Based Configuration:** Assigns backup policies based on the `RecoveryServicesVault` and `BackupPolicy` tags found on VMs.
- **Backup Status Tracking:** Keeps track of the backup status for each VM, indicating whether a VM is protected or not.
- **Enhanced Policy Fallback:** If the assignment of the specified backup policy fails, the script attempts to assign an "EnhancedPolicy" (a default policy in the Recovery Services Vault).

## Prerequisites

- **Azure PowerShell Module:** Ensure that the Azure PowerShell module is installed and up to date.
- **Custom Module:** The script expects a custom module located at
  `./scripts/modules/*.psm1`

  This module should contain the function `Get-RecoveryServicesVaultAndBackupPolicies`.

## Usage

1. **Import the Function:** Import the `Check-TagsAndAssignBackupPolicy` function into your PowerShell session.
2. **Execute the Script:** Run the function, optionally providing a list of excluded subscription IDs:

   ```powershell
   Check-TagsAndAssignBackupPolicy -ExcludedSubscriptionIds "sub-id-1", "sub-id-2"
   ```

Review Output: The script provides detailed logging and will print a table summarizing the VMs, their backup policies, protection status, and associated Recovery Services Vaults.

### Parameters

- `ExcludedSubscriptionIds` (Optional): An array of subscription IDs to exclude from processing.

### Customization

Feel free to modify the script to fit your specific requirements, such as adding additional logging, adjusting the backup policies, or implementing additional error handling.

## License

This project is licensed under the MIT License. See the LICENSE.md file for details.

## Contributing

Contributions are welcome! Please feel free to submit a pull request or open an issue for any enhancements or bug fixes.

Created by [seb07]
