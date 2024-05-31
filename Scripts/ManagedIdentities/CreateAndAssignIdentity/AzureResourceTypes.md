### Azure Resource Types Reference Table

| Resource Name | Resource Type Identifier | Common Roles |
|---------------|--------------------------|--------------------|
| App Configuration | `Microsoft.AppConfiguration/configurationStores` | "App Configuration Data Reader" <br> "App Configuration Data Owner" |
| Key Vault | `Microsoft.KeyVault/vaults` | "Key Vault Secrets User" <br>OR `"permissions": {"secrets": ["get", "list"]}` |
| Storage Account | `Microsoft.Storage/storageAccounts` | "Storage Blob Data Contributor" |
| Service Bus | `Microsoft.ServiceBus/namespaces` | "Azure Service Bus Data Sender" |
| Service Bus Topic | `Microsoft.ServiceBus/namespaces/topics` | Azure Service Bus Data Sender |
| Cosmos DB SQL | `Microsoft.DocumentDB/databaseAccounts` | "Cosmos DB Built-in Data Contributor" |
| Cosmos DB TABLE | `Microsoft.DocumentDB/databaseAccounts` | "Storage Table Data Contributor" |

### Explanation of Table Columns

- **Resource Name**: This is a friendly name for the resource, used for easy identification.
- **Resource Type Identifier**: The official Azure resource type identifier used in scripts and Azure CLI commands.
- **Common Roles**: Frequently used roles for the resource type, such as data reader, secrets user, or data sender.

