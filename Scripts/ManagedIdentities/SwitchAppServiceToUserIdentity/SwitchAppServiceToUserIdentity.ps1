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

function Get-AppType {
    param ([string]$resourceGroup, [string]$appName)
    $appTypeQuery = az resource show --resource-group $resourceGroup --name $appName --resource-type "Microsoft.Web/sites" --query "kind" -o tsv
    $appType = if ($appTypeQuery -like "*functionapp*") { "FunctionApp" } else { "WebApp" }
    return $appType
}

function Update-AppSettings {
    param (
        [string]$resourceGroup,
        [string]$appName,
        [hashtable]$settings,
        [array]$slots,
        [bool]$skipProdSlotUpdate
    )
    Write-Host "Updating app settings for $appName" -ForegroundColor Yellow
    # Check if settings are empty
    if ($settings.Count -eq 0) {
        Write-Host "No app settings found to update." -ForegroundColor Cyan
        return
    }
    $jsonAppSettings = ($settings | ConvertTo-Json -Compress) -replace '"', '\"'
    Write-Host "App settings: $jsonAppSettings" -ForegroundColor Cyan
    if (-Not $skipProdSlotUpdate) {
        Write-Host "Updating app settings for production slot." -ForegroundColor Cyan
        az webapp config appsettings set --resource-group $resourceGroup --name $appName --settings $jsonAppSettings
    } else {
        Write-Host "Skipping updating app settings for production slot." -ForegroundColor Cyan
    }
    
    if ($null -ne $slots -and $slots.Count -gt 0) {
        foreach ($slot in $slots) {
            Write-Host "Updating same settings for slot: $($slot.name)" -ForegroundColor Cyan
            az webapp config appsettings set --resource-group $resourceGroup --name $appName --settings $jsonAppSettings --slot $slot.name
        }
    }
    else {
        Write-Host "No slots found to update." -ForegroundColor Cyan
    }
}

function Update-KeyVaultReference {
    param (
        [string]$resourceGroup,
        [string]$appName,
        [string]$miId,
        [array]$slots,
        [bool]$skipProdSlotUpdate
    )
    Write-Host "Updating KeyVault reference for $appName" -ForegroundColor Yellow

    $appType = Get-AppType -resourceGroup $resourceGroup -appName $appName
    if ($appType -eq "FunctionApp") {
        if (-Not $skipProdSlotUpdate) {
            Write-Host "Updating KeyVault reference for production slot." -ForegroundColor Cyan
            az functionapp update --resource-group $resourceGroup --name $appName --set "keyVaultReferenceIdentity=$miId"
        }else {
            Write-Host "Skipping updating KeyVault reference for production slot." -ForegroundColor Cyan
        }
        
        if ($null -ne $slots -and $slots.Count -gt 0) {
            foreach ($slot in $slots) {
                Write-Host "Updating KeyVault reference for slot: $($slot.name)" -ForegroundColor Cyan
                az functionapp update --resource-group $resourceGroup --name $appName --set "keyVaultReferenceIdentity=$miId" --slot $slot.name
            }
        }
        else {
            Write-Host "No slots found to update." -ForegroundColor Cyan
        }
    }
    elseif ($appType -eq "WebApp") {
        if(-Not $skipProdSlotUpdate) {
            Write-Host "Updating KeyVault reference for production slot." -ForegroundColor Cyan
            az webapp update --resource-group $resourceGroup --name $appName --set "keyVaultReferenceIdentity=$miId"
        } else {
            Write-Host "Skipping updating KeyVault reference for production slot." -ForegroundColor Cyan
        }
        
        if ($null -ne $slots -and $slots.Count -gt 0) {
            foreach ($slot in $slots) {
                Write-Host "Updating KeyVault reference for slot: $($slot.name)" -ForegroundColor Cyan
                az webapp update --resource-group $resourceGroup --name $appName --set "keyVaultReferenceIdentity=$miId" --slot $slot.name
            }
        }
        else {
            Write-Host "No slots found to update." -ForegroundColor Cyan
        }
    }
}

function Get-IdentityDetails {
    param (
        [string]$identityName,
        [string]$resourceGroup
    )

    $identityData = az identity show --name $identityName --resource-group $resourceGroup | ConvertFrom-Json
    if (-Not $identityData) {
        Write-Host "Managed Identity with name $identityName not found in resource group $resourceGroup." -ForegroundColor Red
        return $null
    }
    return @{
        Id          = $identityData.id
        ClientId    = $identityData.clientId
        PrincipalId = $identityData.principalId
    }
}

function Get-AssignedIdentity {
    param (
        [string]$appName,
        [string]$resourceGroup,
        [string]$identityName
    )

    Write-Host "Fetching assigned identity for $appName" -ForegroundColor Yellow
    # Fetch web app details
    $webAppIdentities = az webapp identity show --name $appName --resource-group $resourceGroup | ConvertFrom-Json
    if (-Not $webAppIdentities) {
        Write-Host "Web App with name $appName not found in resource group $resourceGroup." -ForegroundColor Red
        return $null
    }

    # Initialize identityDetails variable
    $identityData = $null
    # Check for user-assigned managed identity
    if($webAppIdentities.userAssignedIdentities.PSObject.Properties.Count -eq 0){
        Write-Host "No identities found for $appName." -ForegroundColor Red
        $identityData = $null
    }
    elseif ($app.PSObject.Properties.Name -contains 'managedIdentityName' -and $app.managedIdentityName) {
        $identityData = Get-IdentityDetails -identityName $app.managedIdentityName -resourceGroup $resourceGroup
        if ( -Not $identityData) {
            <# Action to perform if the condition is true #>
            Write-Host "Specified identity $($app.managedIdentityName) not found in resource group $resourceGroup." -ForegroundColor Red
            return $null
        }
        if (-Not $webAppIdentities.userAssignedIdentities.PSObject.Properties.Name.Contains($identityData.id)) {
            Write-Host "Specified identity $($app.managedIdentityName) is not assigned to $appName." -ForegroundColor Red
            $identityData = $null
        } else {
            Write-Host "Found specified identity '$($identityData.ClientId)' for $appName" -ForegroundColor Green
        }
    }
    elseif ($webAppIdentities.userAssignedIdentities.PSObject.Properties.Count -eq 1) {
        $identityKey = $webAppIdentities.userAssignedIdentities.PSObject.Properties.Name
        $identityValue = $webAppIdentities.userAssignedIdentities.PSObject.Properties.Value
        $identityData = @{
            Id          = $identityKey
            ClientId    = $identityValue.clientId
            PrincipalId = $identityValue.principalId
        }
        Write-Host "Fetched identity '$($identityData.ClientId)' for $appName" -ForegroundColor Green
    }
    else {
        Write-Host "Multiple identities found for $appName and no specific identity specified." -ForegroundColor Red
        $identityData = $null
        # return
    }

    return $identityData
}

function Update-AppAdditionalSettings {
    param (
        [string]$resourceGroup,
        [string]$appName,
        [hashtable]$settings,
        [array]$slots,
        [bool]$skipProdSlotUpdate
    )
    Write-Host "Adding additional settings for $appName" -ForegroundColor Yellow
    Update-AppSettings -resourceGroup $resourceGroup -appName $appName -settings $settings -slots $slots -skipProdSlotUpdate $skipProdSlotUpdate
    Write-Host "Completed adding additional settings" -ForegroundColor Green
}

function Switch-ToUserAssignedIdentity {
    param (
        [string]$resourceGroup,
        [string]$appName,
        [string]$miId,
        [string]$clientId,
        [array]$slots,
        [bool]$skipProdSlotUpdate
    )
    Write-Host "Switching App to User Assigned Identity" -ForegroundColor Yellow
    $appSettings = @{
        "AZURE_CLIENT_ID" = $clientId
        "AZURE_TENANT_ID" = "72f988bf-86f1-41af-91ab-2d7cd011db47"
    }
    Write-Host "Updating app settings and KeyVault reference for $appName" -ForegroundColor Cyan
    Update-AppSettings -resourceGroup $resourceGroup -appName $appName -settings $appSettings -slots $slots -skipProdSlotUpdate $skipProdSlotUpdate
    Update-KeyVaultReference -resourceGroup $resourceGroup -appName $appName -miId $miId -slots $slots -skipProdSlotUpdate $skipProdSlotUpdate
}

# Get configuration
$config = Get-Configuration -configFilePath $configFilePath

# Check if configuration is valid
if (-not $config.appList) {
    Write-Error "Invalid configuration file: $configFilePath"
    exit 1
}

####### APP ########

foreach ($app in $config.appList) {
    Write-Host "Processing app: $($app.name)" -ForegroundColor Yellow

    # if skipProdSlotUpdate is not provided in the config, set it to false
    $skipProdSlotUpdate = if ($null -eq $app.skipProdSlotUpdate) { $false } else { $app.skipProdSlotUpdate }
    
    Write-Host "skipProdSlotUpdate: $skipProdSlotUpdate" -ForegroundColor Cyan
    
    # if niether switchToUserAssignedIdentity nor updateAdditionalSettings is true, skip the app
    if (-Not $app.switchToUserAssignedIdentity -and -Not $app.updateAdditionalSettings) {
        Write-Host "No action specified for app: $($app.name). Skipping..." -ForegroundColor Red
        continue
    }

    # if skip prod slot update and no other slot updates required, skip the app
    if ($skipProdSlotUpdate -and -Not $app.updateSlots) {
        Write-Host "No SLOT action specified for app: $($app.name). Skipping..." -ForegroundColor Red
        continue
    }

    # Get user assigned identity details
    $identityDetails = Get-AssignedIdentity -appName $app.name -resourceGroup $app.resourceGroup -identityName $app.managedIdentityName
    if (-Not $identityDetails) {
        Write-Host "No User Assigned Identity found for app: $($app.name). Skipping..." -ForegroundColor Red
        continue
    }

    # Get slots if updateSlots is true
    if ($app.updateSlots) {
        $slots = az webapp deployment slot list --name $app.name --resource-group $app.resourceGroup | ConvertFrom-Json
    } else {
        $slots = @()
    }
    
    # Add additional settings to app and slots if they exist
    if ($app.updateAdditionalSettings -and $app.additionalSettings) {
        $additionalSettings = @{}
        foreach ($prop in $app.additionalSettings.PSObject.Properties) {
            # if $prop.Value == __UAMI__, then add the identity client id
            if ($prop.Value -eq "__UAMI__") {
                $additionalSettings[$prop.Name] = $identityDetails.clientId
                continue
            }
            $additionalSettings[$prop.Name] = $prop.Value
        }
        Update-AppAdditionalSettings -resourceGroup $app.resourceGroup -appName $app.name -settings $additionalSettings -slots $slots -skipProdSlotUpdate $skipProdSlotUpdate
    }

    # Update app settings and KeyVault reference based on user assigned identity switch
    if ($app.switchToUserAssignedIdentity) {
        Switch-ToUserAssignedIdentity -resourceGroup $app.resourceGroup -appName $app.name -miId $identityDetails.id -clientId $identityDetails.clientId -slots $slots -skipProdSlotUpdate $skipProdSlotUpdate
    }
}