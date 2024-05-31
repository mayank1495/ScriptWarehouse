# PowerShell Script for Switching Azure App Service to User Assigned Identity

This PowerShell script configures Azure App Services to use User Assigned Identities by updating app settings with identity credentials (`AZURE_CLIENT_ID` and `AZURE_TENANT_ID`). This is critical for applications that rely on specific Azure Managed Identities to access Azure services securely. The script checks if a User Assigned Identity is already associated with the App Service and updates the application settings accordingly. It also handles additional app settings specified in the configuration file.

## Prerequisites

- PowerShell 5.1 or higher.
- Azure CLI (latest version recommended).
- An Azure subscription with permissions to manage Azure App Services and Managed Identities.

## Configuration File Structure

The JSON configuration file is used to specify which applications need their identity settings updated:

- **`appList`**: An array of applications, each with the following properties:
  - `name`: Name of the Azure App Service.
  - `resourceGroup`: Resource group where the App Service is located.
  - `switchToUserAssignedIdentity`: Boolean indicating whether to update the app to use a User Assigned Identity.
  - `updateSlots`: Boolean indicating whether to apply settings to deployment slots.
  - `skipProdSlotUpdate`: (Optional) Boolean indicating whether to skip updating the production slot. If not provided, it defaults to `false`.
  - `managedIdentityName`: (Optional) Specifies a particular User Assigned Identity to use, necessary if multiple identities are associated with the App Service.
  - `updateAdditionalSettings`: Boolean indicating whether to update additional app settings.
  - `additionalSettings`: Key-value pairs of other app settings to be updated, regardless of identity settings.

It is recommended to group apps together in the configuration file that are within the same resource group for organizational simplicity. However, there are no restrictions on how apps can be grouped together in the configuration.

### Example Configuration File

```json
{
  "appList": [
    {
      "name": "Example-AppService",
      "resourceGroup": "ExampleResourceGroup-1",
      "switchToUserAssignedIdentity": true,
      "updateSlots": true,
      "additionalSettings": {
        "ExampleAppConfigEndpoint": "https://example.azconfig.io",
        "ServiceBus__FullyQualifiedNamespace": "example.servicebus.windows.net"
      }
    },
    {
      "name": "Example-FunctionApp",
      "resourceGroup": "ExampleResourceGroup-2",
      "switchToUserAssignedIdentity": false,
      "managedIdentityName": "Example-UserAssignedIdentity-1",
      "updateSlots": true,
      "additionalSettings": {
        "ExampleAppConfigEndpoint": "https://example.azconfig.io"
      }
    }
  ]
}
```

## Script Functions

1. **Get-Configuration**: Loads and validates the configuration from the specified file.
2. **Get-AssignedIdentity**: Retrieves details of the User Assigned Identity assigned to the app.
3. **Update-AppSettings**: A generic function that updates specified app settings.
4. **Update-KeyVaultReference**: 
    - Adjusts KeyVault references to use the specified User Assigned Identity. 
    - This is crucial because app settings often include KeyVault references (e.g., `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` or `AzureWebJobsStorage`) that, by default, use the System Assigned Identity.
    - Switching to a User Assigned Identity without updating these references could cause the app to lose access to the secrets stored in KeyVault if the System Assigned Identity's access is later removed or restricted. [Learn more about Azure Key Vault references](https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references?tabs=azure-cli#access-vaults-with-a-user-assigned-identity).
    - NOTE - This cannot be done from the Azure portal UI currently.
5. **Switch-ToUserAssignedIdentity**: Orchestrates the switch by specifically setting the `AZURE_CLIENT_ID` and `AZURE_TENANT_ID` in the app settings, utilizing `Update-AppSettings` to apply these changes.
6. **Update-AppAdditionalSettings**: Adds any specified additional settings to the app.

## Script Execution Flow

1. **Load Configuration**: The script starts by loading the JSON configuration file.
2. **Process Each App**:
   - For each app in the `appList`, it checks for the specified or default User Assigned Identity.
   - If no identity is found, it skips to the next app.
   - If an identity is found, it proceeds based on the `switchToUserAssignedIdentity` flag.
3. **Update Settings**:
   - If `switchToUserAssignedIdentity` is true, apply identity-specific settings (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`) using `Switch-ToUserAssignedIdentity`.
   - Update KeyVault references to ensure they use the User Assigned Identity.
   - Apply additional settings specified in the configuration using `Update-AppAdditionalSettings`.
4. **Apply to Slots**: If `updateSlots` is true, replicate changes across all deployment slots of the app.

## Usage Instructions

1. Ensure you are logged into Azure with `az login`.
2. Customize the configuration JSON file as per your application requirements.
3. Run the script with the path to the configuration file:

```powershell
.\path\to\script.ps1 -configFilePath .\path\to\config.json
```

## Important Notes

- Ensure the User Assigned Identity is already assigned to the App Service and has the necessary roles assigned. This can be achieved using the `CreateAndAssignIdentity.ps1` script.
- Adding `AZURE_CLIENT_ID` and `AZURE_TENANT_ID` switches the identity from System Assigned to User Assigned, which could impact the application's access to resources.
- The script will skip any App Service where the User Assigned Identity is not found or is incorrectly specified.
- If multiple User Assigned Identities are found and no specific identity is mentioned, the script will skip the update for that App Service.
- Updating KeyVault references is critical; failing to do so after switching identities may result in loss of access to key vault secrets, especially if the System Assigned Identity is removed or its permissions are altered.