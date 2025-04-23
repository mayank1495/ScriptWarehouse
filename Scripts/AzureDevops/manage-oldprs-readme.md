# Manage-OldPRs.ps1

Automated **house-keeping for Azure DevOps pull-requests**.  
The script lets you **review** or **abandon** every *active* PR that’s older than a configurable number of days, across one or many repositories.  
Results are exported to CSV, and live progress bars keep you informed during long runs.

---

## Table of Contents

1. [Features](#features)  
2. [Prerequisites](#prerequisites)  
3. [Installation](#installation)  
4. [Quick Start](#quick-start)  
5. [Parameters](#parameters)  
6. [Examples](#examples)  
7. [Output](#output)  
8. [FAQ](#faq)  
9. [Contributing](#contributing)  
10. [License](#license)

---

## Features

| Capability | Details |
|------------|---------|
| **Dual mode** | `fetch` → list stale PRs; `abandon` → close them. |
| **Repo selection** | • Single repo (`-Repository`) • Multiple repos matching a prefix (`-RepoPrefix`) • Entire project (no repo flag). |
| **Age filter** | Anything older than `-OlderThanDays` (default = 30). |
| **CSV audit trail** | Always writes `PRs_{fetch\|abandon}_YYYYMMDD_HHMMSS.csv`. |
| **Progress bars** | 1️⃣ scanning repositories · 2️⃣ abandoning PRs. |
| **Interactive safety** | Confirmation prompt before abandoning (skip with `-Force`). |
| **Idempotent & reversible** | Already-abandoned PRs are ignored; you can re-activate a PR from the DevOps UI if needed. |

---

## Prerequisites

| Component | Minimum version | Install |
|-----------|-----------------|---------|
| **PowerShell** | 5.1 (Windows) / 7+ (cross-platform) | <https://learn.microsoft.com/powershell/> |
| **Azure CLI** | 2.30+ | <https://aka.ms/azure-cli> |
| **DevOps extension** | — | `az extension add --name azure-devops` |
| **Authentication** | — | `az login` *(AAD)* **or** `az devops login --token <PAT>` with *Code & PR-write* scope |

---

## Installation

```bash
# Clone or copy the script into your repo / scripts folder
git clone https://github.com/<org>/<repo>.git
cd <repo>/scripts
```

No further setup—dependencies are auto-checked and installed at runtime.

---

## Quick Start

```powershell
# List all PRs ≥30 days old (default) across every repo
./Manage-OldPrs.ps1 -Mode fetch `
                    -Organization https://dev.azure.com/contoso `
                    -Project Platform

# Abandon the same set after review
./Manage-OldPrs.ps1 -Mode abandon `
                    -Organization https://dev.azure.com/contoso `
                    -Project Platform -Force
```

---

## Parameters

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `-Mode` | ✔ | `fetch` | `fetch` = list only, `abandon` = close PRs. |
| `-Organization` | ✔ | — | Full DevOps org URL. |
| `-Project` | ✔ | — | Project name or GUID. |
| `-Repository` | — | — | Single repo to process. |
| `-RepoPrefix` | — | — | Process all repos starting with this text. |
| `-OlderThanDays` | — | 30 | Age threshold in days. |
| `-Force` | — | *false* | Suppress confirmation in **abandon** mode. |

> `-Repository` and `-RepoPrefix` are mutually exclusive.

---

## Examples

### 1 – Review stale PRs in HR repos

```powershell
./Manage-OldPrs.ps1 -Mode fetch `
                    -Organization https://dev.azure.com/contoso `
                    -Project HRPlatform -RepoPrefix "hr-"
```

### 2 – Close PRs > 60 days old in a legacy repo

```powershell
./Manage-OldPrs.ps1 -Mode abandon `
                    -Organization https://dev.azure.com/contoso `
                    -Project Infra -Repository "legacy-api" `
                    -OlderThanDays 60 -Force
```

### 3 – Nightly pipeline clean-up

```yaml
# azure-pipelines.yml
- task: PowerShell@2
  inputs:
    filePath: scripts/Manage-OldPrs.ps1
    arguments: >
      -Mode abandon
      -Organization $(System.CollectionUri)
      -Project    $(System.TeamProject)
      -OlderThanDays 45
      -Force
  displayName: 'Prune stale pull-requests'
```

---

## Output

| Column | Notes |
|--------|-------|
| `Id` | PR ID in DevOps. |
| `Repository` | Repo name. |
| `Title` | PR title. |
| `Author` / `AuthorEmail` | Creator. |
| `CreationDate` | UTC timestamp. |
| `AgeDays` | Integer age at run-time. |
| `Status` | `Active` (fetch) or `Abandoned` (after clean-up). |
| `Url` | Direct link to PR. |
| `AbandonDate` | Populated only when a PR is abandoned. |

---

## FAQ

**Is abandoning permanent?**  
No. Any PR can be re-activated in the Azure DevOps UI.

**Will it touch completed / draft PRs?**  
No. The script filters on `status = active` only.

**What if I re-run the script?**  
Already-abandoned PRs are skipped; new CSVs are generated with fresh timestamps.

**How do I change the CSV location?**  
Edit the `Export-PrCsv` function near the bottom of the script.

---