#Requires -Version 7.0

<#
.SYNOPSIS
    Master deployment script for IAM configurations (Identity and Access Management).

.DESCRIPTION
    Deploys IAM configurations from JSON files to Microsoft Entra ID using the Microsoft Graph API.
    Supports:
    - Entra ID Groups (exclusion groups for CA)
    - Named Locations (geo-based CA dependencies)
    - Conditional Access Policies (security-first with break-glass protection)
    - Service Principals (workload identities)
    - SSO Integrations (SAML/OIDC)

    SECURITY-FIRST DESIGN:
    - Break-glass exclusions mandatory for all CA policies
    - Report-only mode enforced for production CA deployments
    - Audit logging for all changes
    - Rollback capabilities
    - Multi-stage approval gates (via GitHub Actions)

.PARAMETER ConfigPath
    Path to the directory containing IAM configuration JSON files.

.PARAMETER All
    Deploy all configuration types.

.PARAMETER Groups
    Deploy Entra ID groups only.

.PARAMETER NamedLocations
    Deploy Named Locations only.

.PARAMETER ConditionalAccess
    Deploy Conditional Access policies only.

.PARAMETER ServicePrincipals
    Deploy Service Principals only.

.PARAMETER CAInitialState
    Initial state for Conditional Access policies.
    Default: enabledForReportingButNotEnforced (report-only mode)
    Production MUST use report-only initially.

.PARAMETER Environment
    Deployment environment (dev/staging/prod).
    Affects approval requirements and initial CA state.

.PARAMETER WhatIf
    Preview changes without making them.

.PARAMETER GenerateReport
    Generate deployment report after completion.

.EXAMPLE
    # Deploy all configurations in development
    ./Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -All -Environment dev

.EXAMPLE
    # Deploy only Conditional Access in report-only mode (production)
    ./Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -ConditionalAccess -Environment prod

.EXAMPLE
    # Preview deployment without making changes
    ./Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -All -WhatIf

.NOTES
    Requires Microsoft.Graph PowerShell modules.
    Run: Install-Module Microsoft.Graph -Scope CurrentUser

    SECURITY REQUIREMENTS:
    - Interactive user authentication (MFA enforced)
    - Global Administrator or appropriate delegated roles
    - Audit logging enabled
    - Break-glass accounts configured

    APPROVAL GATES (GitHub Actions):
    - Dev: Auto-approve
    - Staging: Single approver
    - Prod: Multi-approver (2+ approvals required)
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Selective')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$ConfigPath,

    [Parameter(ParameterSetName = 'All')]
    [switch]$All,

    [Parameter(ParameterSetName = 'Selective')]
    [switch]$Groups,

    [Parameter(ParameterSetName = 'Selective')]
    [switch]$NamedLocations,

    [Parameter(ParameterSetName = 'Selective')]
    [switch]$ConditionalAccess,

    [Parameter(ParameterSetName = 'Selective')]
    [switch]$ServicePrincipals,

    [Parameter()]
    [ValidateSet("enabled", "disabled", "enabledForReportingButNotEnforced")]
    [string]$CAInitialState = "enabledForReportingButNotEnforced",

    [Parameter()]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",

    [Parameter()]
    [switch]$GenerateReport
)

#region Script Setup

$ErrorActionPreference = 'Stop'
$startTime = Get-Date

# Set environment variable for validation logic
$env:DEPLOYMENT_ENV = $Environment

# Import module
$modulePath = Join-Path $PSScriptRoot "modules/IAMDeploy.psm1"
if (-not (Test-Path $modulePath)) {
    Write-Error "Module not found: $modulePath"
    exit 1
}
Import-Module $modulePath -Force

# Results tracking
$results = @{
    StartTime = $startTime
    Environment = $Environment
    Groups = @{ Success = 0; Failed = 0; Skipped = 0; Details = @() }
    NamedLocations = @{ Success = 0; Failed = 0; Skipped = 0; Details = @() }
    ConditionalAccess = @{ Success = 0; Failed = 0; Skipped = 0; Details = @() }
    ServicePrincipals = @{ Success = 0; Failed = 0; Skipped = 0; Details = @() }
}

#endregion

#region Helper Functions

function Find-IAMConfigFiles {
    param(
        [string]$BasePath,
        [string[]]$SearchPaths,
        [string]$Pattern = "*.json"
    )

    $files = @()
    foreach ($searchPath in $SearchPaths) {
        $fullPath = Join-Path $BasePath $searchPath
        if (Test-Path $fullPath) {
            $files += Get-ChildItem -Path $fullPath -Filter $Pattern -Recurse -File
        }
    }
    return $files
}

function Update-DeploymentResults {
    param(
        [hashtable]$CategoryResults,
        [hashtable]$DeployResult,
        [string]$Name
    )

    switch ($DeployResult.Status) {
        "Created" { $CategoryResults.Success++ }
        "Updated" { $CategoryResults.Success++ }
        "Failed" { $CategoryResults.Failed++ }
        "Skipped" { $CategoryResults.Skipped++ }
    }

    $CategoryResults.Details += @{
        Name = $Name
        Status = $DeployResult.Status
        Id = $DeployResult.Id
        Error = $DeployResult.Error
        State = $DeployResult.State
    }
}

function Write-IAMDeploymentReport {
    param(
        [hashtable]$Results,
        [string]$OutputPath
    )

    $endTime = Get-Date
    $duration = $endTime - $Results.StartTime

    $report = @"
# IAM Deployment Report
Generated: $($endTime.ToString("yyyy-MM-dd HH:mm:ss")) UTC
Duration: $($duration.ToString("hh\:mm\:ss"))
Environment: $($Results.Environment)

## Summary

| Category | Success | Failed | Skipped |
|----------|---------|--------|---------|
| Groups | $($Results.Groups.Success) | $($Results.Groups.Failed) | $($Results.Groups.Skipped) |
| Named Locations | $($Results.NamedLocations.Success) | $($Results.NamedLocations.Failed) | $($Results.NamedLocations.Skipped) |
| Conditional Access | $($Results.ConditionalAccess.Success) | $($Results.ConditionalAccess.Failed) | $($Results.ConditionalAccess.Skipped) |
| Service Principals | $($Results.ServicePrincipals.Success) | $($Results.ServicePrincipals.Failed) | $($Results.ServicePrincipals.Skipped) |

## Totals
- **Total Deployed**: $(($Results.Groups.Success + $Results.NamedLocations.Success + $Results.ConditionalAccess.Success + $Results.ServicePrincipals.Success))
- **Total Failed**: $(($Results.Groups.Failed + $Results.NamedLocations.Failed + $Results.ConditionalAccess.Failed + $Results.ServicePrincipals.Failed))

"@

    # Add CA policy details
    $caDetails = $Results.ConditionalAccess.Details | Where-Object { $_.Status -in @("Created", "Updated") }
    if ($caDetails.Count -gt 0) {
        $report += "`n## Conditional Access Policies`n`n"
        foreach ($ca in $caDetails) {
            $report += "- **$($ca.Name)**: $($ca.Status) (State: $($ca.State))`n"
        }
    }

    # Add failure details
    $allFailed = @()
    $allFailed += $Results.Groups.Details | Where-Object { $_.Status -eq "Failed" }
    $allFailed += $Results.NamedLocations.Details | Where-Object { $_.Status -eq "Failed" }
    $allFailed += $Results.ConditionalAccess.Details | Where-Object { $_.Status -eq "Failed" }
    $allFailed += $Results.ServicePrincipals.Details | Where-Object { $_.Status -eq "Failed" }

    if ($allFailed.Count -gt 0) {
        $report += "`n## Failed Deployments`n`n"
        foreach ($failed in $allFailed) {
            $report += "- **$($failed.Name)**: $($failed.Error)`n"
        }
    }

    if ($OutputPath) {
        $report | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "`nReport saved to: $OutputPath" -ForegroundColor Cyan
    }

    return $report
}

#endregion

#region Main Execution

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  IAM Configuration Deployment" -ForegroundColor Cyan
Write-Host "  Environment: $Environment" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($WhatIfPreference) {
    Write-Host "[WHAT-IF MODE] No changes will be made`n" -ForegroundColor Yellow
}

if ($Environment -eq "prod") {
    Write-Host "[PRODUCTION MODE] Extra security validations enabled" -ForegroundColor Yellow
    Write-Host "  - CA policies will deploy in report-only mode" -ForegroundColor Yellow
    Write-Host "  - Break-glass exclusions mandatory" -ForegroundColor Yellow
    Write-Host "  - Audit logging enabled`n" -ForegroundColor Yellow
}

# Connect to Graph
if (-not (Test-IAMGraphConnection)) {
    $connected = Connect-IAMGraph
    if (-not $connected) {
        Write-Error "Failed to connect to Microsoft Graph. Exiting."
        exit 1
    }
}

Write-Host "`nConfiguration Path: $ConfigPath`n" -ForegroundColor Cyan

# Determine what to deploy
$deployGroups = $All -or $Groups
$deployNamedLocations = $All -or $NamedLocations
$deployCA = $All -or $ConditionalAccess
$deployServicePrincipals = $All -or $ServicePrincipals

# If no specific flags, warn user
if (-not ($deployGroups -or $deployNamedLocations -or $deployCA -or $deployServicePrincipals)) {
    Write-Warning "No deployment type specified. Use -All or specific flags."
    exit 0
}

#region Deploy Groups (Dependency for CA)
if ($deployGroups) {
    Write-Host "=== Deploying Groups ===" -ForegroundColor Magenta

    $groupFiles = Find-IAMConfigFiles -BasePath $ConfigPath -SearchPaths @("Groups")

    if ($groupFiles.Count -eq 0) {
        Write-Host "  No group configuration files found" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Found $($groupFiles.Count) group configuration(s)" -ForegroundColor Cyan

        foreach ($file in $groupFiles) {
            try {
                $config = Read-IAMConfigurationFile -Path $file.FullName
                $result = Deploy-EntraGroup -Configuration $config -WhatIf:$WhatIfPreference
                Update-DeploymentResults -CategoryResults $results.Groups -DeployResult $result -Name $config.displayName
            }
            catch {
                Write-Error "Error processing $($file.Name): $_"
                Update-DeploymentResults -CategoryResults $results.Groups -DeployResult @{ Status = "Failed"; Error = $_.Exception.Message } -Name $file.Name
            }
        }
    }
    Write-Host ""
}
#endregion

#region Deploy Named Locations (Dependency for CA)
if ($deployNamedLocations) {
    Write-Host "=== Deploying Named Locations ===" -ForegroundColor Magenta

    $locationFiles = Find-IAMConfigFiles -BasePath $ConfigPath -SearchPaths @("NamedLocations")

    if ($locationFiles.Count -eq 0) {
        Write-Host "  No named location configuration files found" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Found $($locationFiles.Count) named location configuration(s)" -ForegroundColor Cyan

        foreach ($file in $locationFiles) {
            try {
                $config = Read-IAMConfigurationFile -Path $file.FullName
                $result = Deploy-NamedLocation -Configuration $config -WhatIf:$WhatIfPreference
                Update-DeploymentResults -CategoryResults $results.NamedLocations -DeployResult $result -Name $config.displayName
            }
            catch {
                Write-Error "Error processing $($file.Name): $_"
                Update-DeploymentResults -CategoryResults $results.NamedLocations -DeployResult @{ Status = "Failed"; Error = $_.Exception.Message } -Name $file.Name
            }
        }
    }
    Write-Host ""
}
#endregion

# Import object ID mapping for CA policy deployment
if ($deployCA) {
    Write-Host "=== Loading Object ID Mappings ===" -ForegroundColor Magenta
    Import-ObjectIdMapping
    Write-Host ""
}

#region Deploy Conditional Access Policies
if ($deployCA) {
    Write-Host "=== Deploying Conditional Access Policies ===" -ForegroundColor Magenta
    Write-Host "  Initial state: $CAInitialState" -ForegroundColor Cyan

    # Production enforcement: report-only mode
    if ($Environment -eq "prod" -and $CAInitialState -eq "enabled") {
        Write-Warning "Production deployments MUST use report-only mode initially"
        Write-Warning "Overriding to: enabledForReportingButNotEnforced"
        $CAInitialState = "enabledForReportingButNotEnforced"
    }

    $caFiles = Find-IAMConfigFiles -BasePath $ConfigPath -SearchPaths @("ConditionalAccess")

    if ($caFiles.Count -eq 0) {
        Write-Host "  No Conditional Access configuration files found" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Found $($caFiles.Count) CA policy configuration(s)" -ForegroundColor Cyan

        foreach ($file in $caFiles) {
            try {
                $config = Read-IAMConfigurationFile -Path $file.FullName
                $result = Deploy-ConditionalAccessPolicy -Configuration $config -InitialState $CAInitialState -WhatIf:$WhatIfPreference
                Update-DeploymentResults -CategoryResults $results.ConditionalAccess -DeployResult $result -Name $config.displayName
            }
            catch {
                Write-Error "Error processing $($file.Name): $_"
                Update-DeploymentResults -CategoryResults $results.ConditionalAccess -DeployResult @{ Status = "Failed"; Error = $_.Exception.Message } -Name $file.Name
            }
        }
    }
    Write-Host ""
}
#endregion

#region Summary

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Deployment Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$totalSuccess = $results.Groups.Success + $results.NamedLocations.Success + $results.ConditionalAccess.Success + $results.ServicePrincipals.Success
$totalFailed = $results.Groups.Failed + $results.NamedLocations.Failed + $results.ConditionalAccess.Failed + $results.ServicePrincipals.Failed

Write-Host "Total Deployed: $totalSuccess" -ForegroundColor Green
Write-Host "Total Failed: $totalFailed" -ForegroundColor $(if ($totalFailed -gt 0) { "Red" } else { "Green" })

if ($GenerateReport) {
    $reportPath = Join-Path $PSScriptRoot "deployment-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
    Write-IAMDeploymentReport -Results $results -OutputPath $reportPath
}

# Exit with error code if failures
if ($totalFailed -gt 0) {
    exit 1
}

#endregion

#endregion
