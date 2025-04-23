<#
    Manage-OldPrs-ADO.ps1
    -----------------
    Fetches (lists) or abandons “active” pull requests in Azure DevOps
    Repos that are older than a configurable age.  Results are exported
    to CSV, and long-running operations now show a live progress bar.

    REQUIREMENTS
      • Windows PowerShell 5.1 or PowerShell 7+
      • Azure CLI 2.30+                  →  https://aka.ms/azure-cli
      • Azure DevOps extension           →  az extension add --name azure-devops
      • Auth:  az login      (Azure AD)       –or–
               az devops login --token <PAT>  (Classic PAT)

    EXAMPLES
      # 1 Preview stale PRs (>30 days) in repos that start with “hr-”
      ./Manage-OldPrs-ADO.ps1 -Mode fetch `
                          -Organization https://dev.azure.com/contoso `
                          -Project HRPlatform -RepoPrefix "hr-" -OlderThanDays 30

      # 2 Abandon PRs >60 days old in repo “legacy-api” (non-interactive)
      ./Manage-OldPrs-ADO.ps1 -Mode abandon `
                          -Organization https://dev.azure.com/contoso `
                          -Project Infra -Repository "legacy-api" `
                          -OlderThanDays 60 -Force

      # 3 Abandon stale PRs across *all* repos and log to CSV
      ./Manage-OldPrs-ADO.ps1 -Mode abandon `
                          -Organization https://dev.azure.com/contoso `
                          -Project Platform -OlderThanDays 45 -Force
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('fetch', 'abandon')]
    [string] $Mode = 'fetch',

    [Parameter(Mandatory)][string] $Organization,
    [Parameter(Mandatory)][string] $Project,

    [string] $Repository,   # process just this repo
    [string] $RepoPrefix,   # or every repo that starts with this text
    [int]    $OlderThanDays = 30,
    [switch] $Force         # skip confirmation when abandoning
)

# --- validation & tooling -------------------------------------------------
if ($Repository -and $RepoPrefix) {
    throw "Specify either -Repository or -RepoPrefix, not both."
}

if (-not (Get-Command az -EA SilentlyContinue)) {
    throw "Azure CLI not found. Install from https://aka.ms/azure-cli"
}

if (-not (az extension list --query "[?name=='azure-devops']" -o tsv)) {
    az extension add --name azure-devops | Out-Null
}

az devops configure --defaults organization=$Organization project=$Project | Out-Null
$cutOff = (Get-Date).AddDays(-$OlderThanDays)

# --- helpers --------------------------------------------------------------
function Get-Repos {
    $all = (az repos list -o json |
            ConvertFrom-Json | Select-Object -Expand name)
    switch ($true) {
        { $Repository } { return @($Repository) }
        { $RepoPrefix } { return $all | Where-Object { $_ -like "$RepoPrefix*" } }
        default         { return $all }
    }
}

function Get-OldActivePrs([string] $RepoName, [int] $ix, [int] $total) {
    Write-Progress -Id 1 -Activity "Scanning repos" `
                   -Status "$RepoName ($ix of $total)" `
                   -PercentComplete ([int](($ix / $total) * 100))

    (az repos pr list --repository $RepoName --status active -o json |
        ConvertFrom-Json) |
        Where-Object { (Get-Date $_.creationDate) -le $cutOff } |
        ForEach-Object {
            [pscustomobject]@{
                Id            = $_.pullRequestId
                Repository    = $RepoName
                Title         = $_.title
                Author        = $_.createdBy.displayName
                AuthorEmail   = $_.createdBy.uniqueName
                CreationDate  = [datetime]$_.creationDate
                AgeDays       = [int]((Get-Date) - $_.creationDate).TotalDays
                Status        = $_.status
                Url           = $_.url
                AbandonDate   = $null
            }
        }
}

function Export-PrCsv($Data, $ModeTag) {
    $name = "PRs_${ModeTag}_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $Data | Sort-Object Repository, CreationDate |
            Export-Csv -Path $name -NoTypeInformation
    Write-Host "📄  CSV written → $name"
}

# --- gather stale PRs -----------------------------------------------------
$repos    = Get-Repos
$stalePrs = @()
$idx      = 0
foreach ($r in $repos) {
    $idx++
    $stalePrs += Get-OldActivePrs $r $idx $repos.Count
}
Write-Progress -Id 1 -Activity "Scanning repos" -Completed

if (-not $stalePrs) {
    Write-Host "✅  No active PRs older than $OlderThanDays day(s)."
    return
}

# --- fetch mode -----------------------------------------------------------
if ($Mode -eq 'fetch') {
    $stalePrs | Format-Table
    Export-PrCsv $stalePrs 'fetch'
    return
}

# --- abandon mode ---------------------------------------------------------
if (-not $Force) {
    $reply = Read-Host "⚠️  Abandon $($stalePrs.Count) PR(s)? (y/N)"
    if ($reply -notin 'y','Y') { Write-Host "Cancelled."; return }
}

$total = $stalePrs.Count
for ($i = 0; $i -lt $total; $i++) {
    $pr = $stalePrs[$i]
    Write-Progress -Id 2 -Activity "Abandoning PRs" `
                   -Status "PR $($i+1) of $total (Repo: $($pr.Repository))" `
                   -PercentComplete ([int](($i+1)/$total*100))

    az repos pr update --id $pr.Id --status abandoned --output none
    $pr.Status      = 'Abandoned'
    $pr.AbandonDate = Get-Date
}
Write-Progress -Id 2 -Activity "Abandoning PRs" -Completed

Export-PrCsv $stalePrs 'abandon'
Write-Host "✅  Completed – abandoned $total PR(s)."
