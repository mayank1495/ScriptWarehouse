# Activate PIM Roles Using PowerShell Script

This PowerShell script is used to fetch and activate Azure Privileged Identity Management (PIM) roles. The script provides various switches to control its behavior.

## Parameters

- `-FetchRoles`: Fetches the roles assigned to the current user and exports them to a CSV file.
- `-ActivateRoles`: Activates the roles specified in the CSV file.
- `-CsvFilePath`: Specifies the path to the CSV file used for fetching and activating roles. Default is "RoleDetails.csv".
- `-Duration`: Specifies the duration in hours for which the roles should be activated. The value should be between 1 and 8. Default is 8.
- `-ValidateActivation`: Validates whether the role activation was successful.

## Usage

### Fetch Roles

To fetch the roles assigned to the current user and export them to a CSV file, use the `-FetchRoles` switch:

```powershell
.\Activate PIM Roles.ps1 -FetchRoles
```

This will create a CSV file named "RoleDetails.csv" in the same directory as the script.

### Activate Roles

To activate the roles specified in the CSV file, use the `-ActivateRoles` switch:

```powershell
.\Activate PIM Roles.ps1 -ActivateRoles
```

This will read the "RoleDetails.csv" file and activate the roles specified in it.

### Specify CSV File Path

To specify a different path for the CSV file, use the `-CsvFilePath` param:

```powershell
.\Activate PIM Roles.ps1 -FetchRoles -CsvFilePath "C:\path\to\yourfile.csv"
```

### Specify Activation Duration

To specify a different duration for role activation, use the `-Duration` param:

```powershell
.\Activate PIM Roles.ps1 -ActivateRoles -Duration 4
```

This will activate the roles for 4 hours.

### Validate Activation

To validate whether the role activation was successful, use the `-ValidateActivation` switch:

```powershell
.\Activate PIM Roles.ps1 -ActivateRoles -ValidateActivation
```

This will activate the roles and then validate whether the activation was successful.

## CSV File Format

The CSV file used for activating roles should have the following columns:

- `RoleName`: The name of the role.
- `Resource`: The resource for which the role is assigned.
- `ResourceType`: The type of the resource.
- `Role_Guid`: The GUID of the role.
- `SubscriptionID`: The ID of the subscription.
- `Reason`: The reason for activating the role.
- `Activate`: Whether to activate the role. Should be either `true` or `false`.

Once the `Reason` and `Activate` columns are filled, run the script to activate those roles. The script will read the CSV file and activate the roles based on the information provided.

Here's an example of how to run the script:

```powershell
.\Activate PIM Roles.ps1 -ActivateRoles
```
This will read the "RoleDetails.csv" file and activate the roles specified in it.

Or run by specifying your file path.

```powershell
.\Activate PIM Roles.ps1 -ActivateRoles -CsvFilePath './path/to/<file>.csv'
```

Make sure to update the CSV file with the roles you want to activate before running the script.

## Note

The script must be run with an account that has the necessary permissions to fetch and activate roles.