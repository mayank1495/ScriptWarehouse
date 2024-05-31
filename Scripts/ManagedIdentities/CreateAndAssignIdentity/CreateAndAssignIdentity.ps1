param(
    [string]$configFilePath
)

function Get-Configuration {
    param (
        [string]$configFilePath
    )
    # Check if the configuration file exists
    if (-Not (Test-Path $configFilePath)) {
        Write-Error "Configuration file not found: $configFilePath"
        exit 1
    }
    
    # Load the configuration file
    $config = Get-Content -Path $configFilePath | ConvertFrom-Json
    Write-Host "Starting script execution for config: $configFilePath" -ForegroundColor Cyan
    return $config
}

function New-ManagedIdentity {
    param (
        [string]$name,
        [string]$resourceGroup
    )
    Write-Host "Creating User Assigned Managed Identity with name: $name" -ForegroundColor Yellow
    $mi = az identity create --name $name --resource-group $resourceGroup | ConvertFrom-Json
    if (-Not $mi) {
        Write-Error "Failed to create Managed Identity"
        exit 1
    }
    Write-Host "Managed Identity '$name' created with ClientID: '$($mi.clientId)' and ObjectId: '$($mi.principalId)'" -ForegroundColor Green
    return $mi
}

function Test-ManagedIdentityAvailability {
    param (
        [string]$clientId,
        [string]$resourceId,
        [int]$maxRetries = 6,
        [int]$retryDelaySeconds = 5
    )
    $retryCount = 0
    $miAvailable = $False
    do {
        try {
            Write-Host "Checking if Managed Identity is available in Azure AD..." -ForegroundColor Cyan
            # $checkMI = az ad sp show --id $clientId --only-show-errors
            $checkMI = az identity show --ids $resourceId
            if ($checkMI) {
                Write-Host "Managed Identity is now available in Azure AD." -ForegroundColor Green
                $miAvailable = $True
            } else {
                Write-Host "Managed Identity not yet available, retrying in $retryDelaySeconds seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds $retryDelaySeconds
                $retryCount++
            }
        } catch {
            Write-Host "Error checking Managed Identity: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Managed Identity not yet available, retrying in $retryDelaySeconds seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds $retryDelaySeconds
            $retryCount++
        }
    } while (-not $miAvailable -and $retryCount -lt $maxRetries)
    
    if (-not $miAvailable) {
        Write-Error "Managed Identity could not be verified in Azure AD after retries."
        exit 1
    }
}

function Set-RolesToResources {
    param (
        [PSCustomObject]$resources,
        [string]$miObjectId
    )
    foreach ($resourceType in $resources) {
        foreach ($instance in $resourceType.instances) {
            Write-Host "Processing resource type: $($resourceType.type) for instance: $($instance.name)" -ForegroundColor Yellow
            if($resourceType.type -eq "Microsoft.ServiceBus/namespaces/topics"){
                #Here name is in the format of "namespaceName/topicName". So extracting namespaceName and topicName
                $namespaceName = $instance.name.Split("/")[0]
                $topicName = $instance.name.Split("/")[1]
                if(-not $namespaceName -or -not $topicName) {
                    Write-Host "Invalid namespaceName or topicName found for instance $($instance.name). Skipping..." -ForegroundColor Red
                    continue
                }
                $resourceId = az servicebus topic show --resource-group $instance.resourceGroup --namespace-name $namespaceName --name $topicName --query id -o tsv
            } else {
                $resourceId = az resource show --resource-type $resourceType.type --name $instance.name --resource-group $instance.resourceGroup --query "id" -o tsv
            }

            if (-Not $resourceId) {
                Write-Host "No resource ID found for instance $($instance.name) in ResourceGroup $($instance.resourceGroup). Skipping..." -ForegroundColor Red
                continue
            }
            
            if ($resourceType.type -eq "microsoft.DocumentDb/databaseAccounts" -and $instance.role -notlike "*table*") {
                Write-Host "Assigning Cosmos role '$($instance.role)' to '$($miObjectId)' for $($instance.name): $($resourceType.type)" -ForegroundColor Cyan
                az cosmosdb sql role assignment create --account-name $instance.name --resource-group $instance.resourceGroup --role-definition-name $instance.role --scope $resourceId --principal-id $miObjectId
            }
            else {
                if ($resourceType.type -eq "Microsoft.KeyVault/vaults" -and $instance.useAccessPolicy) {
                    Write-Host "Applying access policy to KeyVault: $($instance.name)" -ForegroundColor Cyan
                    az keyvault set-policy --name $instance.name --object-id $miObjectId --key-permissions $instance.permissions.keys --secret-permissions $instance.permissions.secrets --certificate-permissions $instance.permissions.certificates
                }

                Write-Host "Assigning role '$($instance.role)' to '$($miObjectId)' for $($instance.name): $($resourceType.type)" -ForegroundColor Cyan
                # az role assignment create --assignee $miObjectId --role $instance.role --scope $resourceId
                az role assignment create --assignee-object-id $miObjectId --assignee-principal-type "ServicePrincipal" --role $instance.role --scope $resourceId
            }
        }
    }
    Write-Host "Completed role assignments for resources." -ForegroundColor Green
}

function Set-IdentityToAppAndSlots {
    param (
        [string]$resourceGroup,
        [string]$appName,
        [string]$miId,
        [array]$slots
    )

    Write-Host "Assigning Managed Identity ID: $miId to App: $appName" -ForegroundColor Yellow
    az webapp identity assign --resource-group $resourceGroup --name $appName --identities $miId
    foreach ($slot in $slots) {
        Write-Host "Assigning Managed Identity for slot: $($slot.name)" -ForegroundColor Cyan
        az webapp identity assign --resource-group $resourceGroup --name $appName --slot $slot.name --identities $miId
    }
}

# Get configuration
$config = Get-Configuration -configFilePath $configFilePath

# Check if configuration is valid
if (-not $config.managedIdentity) {
    Write-Error "Invalid configuration file: $configFilePath"
    exit 1
}

# Check if managedIdentity.principalId is present then run Set-RolesToResources
if ($config.managedIdentity.systemIdentity) {
    Write-Host "Setting roles for system assigned identity" -ForegroundColor Yellow
    Set-RolesToResources -resources $config.resources -miObjectId $config.managedIdentity.systemIdentity
    Write-Host "Script execution completed for config: $configFilePath" -ForegroundColor DarkGreen
    exit 0
}

# Script Execution
Write-Host "Starting script execution for config: $configFilePath" -ForegroundColor DarkGreen

# Create new Managed Identity
$mi = New-ManagedIdentity -name $config.managedIdentity.name -resourceGroup $config.managedIdentity.resourceGroup

# Test Managed Identity availability
Test-ManagedIdentityAvailability -clientId $mi.clientId -resourceId $mi.id

# Set RBAC roles for a Managed Identity in resources.
Set-RolesToResources -resources $config.resources -miObjectId $mi.principalId

####### APP ########

foreach ($app in $config.appList) {
    Write-Host "Starting Identity Assignment for app: $($app.name)" -ForegroundColor Yellow
    # Get slots if updateSlots is true
    if ($app.updateSlots) {
        $slots = az webapp deployment slot list --name $app.name --resource-group $app.resourceGroup | ConvertFrom-Json
    } else {
        $slots = @()
    }

    # Assign Managed Identity to App and its slots
    Set-IdentityToAppAndSlots -resourceGroup $app.resourceGroup -appName $app.name -miId $mi.id -slots $slots
}

Write-Host "Script execution completed for config: $configFilePath" -ForegroundColor DarkGreen