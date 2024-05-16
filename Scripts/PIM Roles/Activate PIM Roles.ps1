#requires -Version 7.2
#requires -Modules @{ModuleName = 'Az.Resources'; ModuleVersion = '6.1.0' }

param(
    [Switch]$FetchRoles,
    [Switch]$ActivateRoles,
    [string]$CsvFilePath = "RoleDetails.csv",
    [ValidateRange(1, 8)]
    [int]$Duration = 8,
    [switch]$ValidateActivation
)

function Get-CurrentUserId {
    try {
        $context = Get-AzContext
        if ($null -eq $context) {
            Connect-AzAccount
        }
    } catch {
        Connect-AzAccount
    }
    $context = $context ?? (Get-AzContext)
    Write-Host "Executing Script For Current User: $($context.Account.Id)" -ForegroundColor DarkMagenta
    $adUser = Get-AzADUser -UserPrincipalName $context.Account.Id
    $principalId = $adUser.Id
    return $principalId
}

function Get-AzAssignedRoleData {
    param(
        [string]$Scope = '/',
        [switch]$ShowActiveRoles
    )
    #Currently not in use.
    if ($ShowActiveRoles) {
        return Get-AzRoleAssignmentScheduleInstance -Scope $Scope -Filter 'asTarget()' -ErrorAction Stop |
        Where-Object { $_.AssignmentType -eq 'Activated' }
    }
    else {
        return Get-AzRoleEligibilitySchedule -Scope $Scope -Filter 'asTarget()' -ErrorAction Stop
    }
}

function Export-RoleAssignmentsToCsv {
    param(
        [String]$Scope = '/',
        [string]$CsvFilePath
    )
    try {
        $results = Get-AzAssignedRoleData -Scope $Scope
        Write-Host "Total roles fetched: $($results.Count)" -ForegroundColor Cyan
        # Create a custom object to handle output and additional column
        $output = $results | ForEach-Object {
            $subscriptionId = $_.Id.Split('/')[2]  # Extract Subscription ID from the Id property
            [PSCustomObject]@{
                RoleName       = $_.RoleDefinitionDisplayName
                Resource       = $_.ScopeDisplayName
                ResourceType   = $_.ScopeType
                Role_Guid      = $_.Name
                SubscriptionID = $subscriptionId
                Reason         = "<reason>"
                Activate       = $false  # Additional column with default false
            }
        }

        $directoryPath = Split-Path -Path $CsvFilePath -Parent
        if ($directoryPath -and -Not (Test-Path -Path $directoryPath)) {
            New-Item -ItemType Directory -Path $directoryPath -Force
        }
        # Export to CSV
        $output | Export-Csv -Path $CsvFilePath -NoTypeInformation
        Write-Host "CSV file created at: $CsvFilePath" -ForegroundColor Green
    }
    catch {
        Write-Error $PSItem
        exit 1
    }
}

function Invoke-ValidateActivation {
    param (
        [string]$Name,
        [string]$Scope
    )

    #TODO: Check if adding retries or timeout is necessary.
    try {
        do {
            $roleActivation = Get-AzRoleAssignmentScheduleRequest -Scope $Scope -Filter 'asTarget()' -ErrorAction Stop | Where-Object { $_.Name -eq $Name }
        } while (-not $roleActivation)
        Write-Host "Role activation complete for $($roleActivation.Name) on $($roleActivation.ScopeDisplayName)." -ForegroundColor Green
    }
    catch {
        Write-Error $PSItem
    }
}

function Invoke-AzRoleActivation {
    param(
        [Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Models.Api20201001Preview.RoleEligibilitySchedule]$RoleData,
        [string]$Reason,
        [int]$Duration = 8
    )

    if (-not $RoleData -or -not $Reason) {
        Write-Error "RoleData/Reason must be specified."
        return
    }

    $roleActivateParams = @{
        Name                            = New-Guid
        Scope                           = $RoleData.ScopeId
        PrincipalId                     = $currentUserPrincipalId
        RoleDefinitionId                = $RoleData.RoleDefinitionId
        RequestType                     = 'SelfActivate'
        LinkedRoleEligibilityScheduleId = $RoleData.Name
        Justification                   = $Reason
        ExpirationType                  = 'AfterDuration'
        ExpirationDuration              = "PT" + $Duration + "H"
    }

    try {
        $response = New-AzRoleAssignmentScheduleRequest @roleActivateParams -ErrorAction Stop
    }
    catch {
        # Write-Error $PSItem.ErrorDetails.Message
        Write-Host $PSItem -ForegroundColor Red
        return
    }

    return $response
}

function Import-RoleDetailsFromCsv {
    param([string]$CsvFilePath)

    if (-Not (Test-Path -Path $CsvFilePath)) {
        Write-Error "The specified CSV file at '$CsvFilePath' does not exist."
        exit 1
    }

    $csv = Import-Csv -Path $CsvFilePath -ErrorAction Stop

    $requiredColumns = @("RoleName", "Resource", "ResourceType", "Role_Guid", "SubscriptionID", "Reason", "Activate")
    $csvColumns = $csv | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

    foreach ($column in $requiredColumns) {
        if ($column -notin $csvColumns) {
            Write-Error "The CSV file does not contain the required column '$column'."
            exit 1
        }
    }

    return $csv
}

function Enable-RolesFromCSV {
    param(
        [string]$CsvFilePath,
        [int]$Duration
    )
    $roleDetailsFromCsv = Import-RoleDetailsFromCsv -CsvFilePath $CsvFilePath
    $roleDataList = Get-AzAssignedRoleData
    $responseList = @()
    foreach ($role in $roleDetailsFromCsv) {
        if ($role.Activate -eq $true) {
            Write-Host "Activating role: $($role.RoleName) for $($role.Resource)" -ForegroundColor Cyan
            if($role.Reason -eq "<reason>" -or $role.Reason -eq "") {
                Write-host "Reason must be specified for role activation." -ForegroundColor Red
                continue
            }
            $roleData = $roleDataList | Where-Object { $_.Name -eq $role.Role_Guid }
            $resp = Invoke-AzRoleActivation -RoleData $roleData -Reason $role.Reason -Duration $Duration
            if ($resp) {
                $responseList += $resp
            }
        }
    }
    if($responseList.Count -eq 0) {
        Write-Host "No roles were activated." -ForegroundColor Yellow
        return
    }
    Write-Host "Role activation process has been initiated." -ForegroundColor Green
    return $responseList
}

# Script execution logic
if (-not $FetchRoles -and -not $ActivateRoles) {
    Write-Error "Please specify either -FetchRoles or -ActivateRole switch."
    exit 1
}

$currentUserPrincipalId = Get-CurrentUserId

if ($FetchRoles) {
    Write-Host "Fetching roles and creating CSV at $CsvFilePath." -ForegroundColor Yellow
    Export-RoleAssignmentsToCsv -CsvFilePath $CsvFilePath
}

if ($ActivateRoles) {
    Write-Host "Starting ActivateRoles for file $CsvFilePath and Duration $Duration hours" -ForegroundColor Yellow
    $roleResponseList = Enable-RolesFromCSV -CsvFilePath $CsvFilePath -Duration $Duration
    if ($ValidateActivation) {
        Write-Host "Starting ValidateActivation for $($roleResponseList.Count) roles." -ForegroundColor Yellow
        foreach ($resp in $roleResponseList) {
            Write-Host "Validating that your activation is successful for $($resp.Name)($($resp.RoleDefinitionDisplayName) -> $($resp.ScopeDisplayName))." -ForegroundColor Cyan
            # $resp | Format-List *
            Invoke-ValidateActivation -Name $resp.Name -Scope $resp.Scope
        }
    }
    Write-Host "Completed Script Execution." -ForegroundColor Green
}