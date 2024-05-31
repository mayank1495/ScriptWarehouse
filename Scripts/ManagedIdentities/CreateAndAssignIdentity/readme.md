# PowerShell Script for Managing Azure Managed Identities and Resource Access

This PowerShell script automates the management of Azure User Assigned Managed Identities. It creates or retrieves existing identities, assigns them to Azure applications, and configures role-based access control (RBAC) or access policies on specified resources according to a JSON configuration file.

## Prerequisites

- PowerShell 5.1 or higher.
- Azure CLI (latest version recommended).
- An Azure subscription with permissions to create and manage Azure resources, roles, and access policies.

## Configuration File Structure

The JSON configuration file contains detailed specifications for the Managed Identity, the applications to which the identity will be assigned, and the resources that will be managed. Below is a breakdown of each section:

- **`managedIdentity`**: Defines the name and resource group for the Managed Identity. If the identity already exists, it will be retrieved; otherwise, a new one will be created.
- **`appList`**: An array of applications that require the Managed Identity to be assigned. Each application object includes:
  - `name`: Name of the application.
  - `resourceGroup`: Resource group in which the application is located.
  - `updateSlots`: A boolean indicating whether to assign the identity to deployment slots as well.
- **`resources`**: Specifies the resources to which the Managed Identity will have access. It supports both RBAC roles and direct access policies for Azure Key Vault. Each resource object includes:
  - `type`: The Azure resource type. Can be found here - [Resource Types](https://learn.microsoft.com/en-us/azure/governance/resource-graph/reference/supported-tables-resources#resources)
  - `instances`: An array of instances of that resource type, each specifying:
    - `name`: Name of the resource instance.
    - `role`: The role to be assigned for RBAC.
    - `resourceGroup`: Resource group of the instance.
    - `useAccessPolicy`: (Optional) A boolean that, when true, indicates that an access policy should be applied to a Key Vault instead of a role assignment.
    - `permissions`: (Optional) Specifies the permissions for the access policy if `useAccessPolicy` is true.

### Example of a Configuration File

```json
{
  "managedIdentity": {
    "name": "Example-MI",
    "resourceGroup": "Example-ResourceGroup"
  },
  "appList": [
    {
      "name": "ExampleApp",
      "resourceGroup": "Example-ResourceGroup",
      "updateSlots": true
    }
  ],
  "resources": [
    {
      "type": "microsoft.AppConfiguration/configurationStores",
      "instances": [
        {
          "name": "Example-AppConfig-1",
          "role": "App Configuration Data Reader",
          "resourceGroup": "Example-ResourceGroup"
        },
        {
          "name": "Example-AppConfig-2",
          "role": "App Configuration Data Reader",
          "resourceGroup": "Example-ResourceGroup-2"
        }
      ]
    },
    {
      "type": "Microsoft.ServiceBus/namespaces",
      "instances": [
        {
          "name": "Example-ServiceBus",
          "resourceGroup": "Example-ResourceGroup",
          "role": "Azure Service Bus Data Sender"
        }
      ]
    },
    {
      "type": "Microsoft.KeyVault/vaults",
      "instances": [
        {
          "name": "ExampleVault",
          "resourceGroup": "Example-ResourceGroup-2",
          "role": "Key Vault Secrets User",
          "useAccessPolicy": true,
          "permissions": {
            "secrets": ["get", "list"],
            "keys": ["get", "list"],
            "certificates": ["get", "list"]
          }
        }
      ]
    }
  ]
}
```

## Script Functions

1. **Get-Configuration**: Loads and validates the configuration from the specified JSON file.
2. **New-ManagedIdentity**: Creates a new or retrieves an existing User Assigned Managed Identity.
3. **Test-ManagedIdentityAvailability**: Ensures the Managed Identity is available in Azure AD, which is essential before beginning role assignments.
4. **Set-RolesToResources**: Applies RBAC roles or access policies to resources as defined in the configuration. Supports conditional access policy application for Key Vaults.
5. **Set-IdentityToAppAndSlots**: Assigns the Managed Identity to specified Azure applications and optionally to their deployment slots.

## Script Execution Flow

1. **Load Configuration**: Start by loading and validating the JSON configuration file.
2. **Process Managed Identity**:
   - Create or retrieve the specified Managed Identity.
   - Verify the availability of the Managed Identity in Azure AD.
3. **Assign Identity to Apps and Resources**:
   - Apply RBAC roles or access policies to each resource listed in `resources`.
   - For each app in the `appList`, assign the Managed Identity and update deployment slots if required.

## Usage

1. Login to Azure using Azure CLI with `az login`.
2. Prepare your configuration JSON file based on the requirements.
3. Execute the script with the path to the configuration file:

```powershell
.\path\to\script.ps1 -configFilePath .\path\to\config.json
```

## Important Notes

- Ensure the roles and permissions specified in the configuration are valid and available in your Azure subscription.
- Running the script multiple times with the same parameters should not result in redundant identity creations or role assignments.
- RBAC roles are assigned according to the configuration. Incorrect role assignments can lead to inadequate permissions or excessive permissions which could pose a security risk.
- When configuring KeyVault access, if the useAccessPolicy is true, the script directly sets access policies on the KeyVault else it sets the rbac.
- Refer to the [Microsoft documentation](https://learn.microsoft.com/en-us/azure/governance/resource-graph/reference/supported-tables-resources#resources) for details on resource types and their roles.
