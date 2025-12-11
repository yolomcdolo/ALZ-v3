#Requires -Version 7.0

<#
.SYNOPSIS
    Master deployment script for Intune configurations.

.DESCRIPTION
    Deploys Intune configurations from JSON files to Microsoft Intune
    using the Microsoft Graph API. Supports:
    - Entra ID Groups (dependencies for CA)
    - Named Locations (dependencies for CA)
    - Conditional Access Policies
    - Device Compliance Policies
    - Windows Update Rings
    - Driver Update Profiles
    - App Protection Policies (MAM)

.PARAMETER ConfigPath
    Path to the directory containing configuration JSON files.

.PARAMETER All
    Deploy all configuration types.

.PARAMETER Groups
    Deploy Entra ID groups only.

.PARAMETER NamedLocations
    Deploy Named Locations only.

.PARAMETER ConditionalAccess
    Deploy Conditional Access policies only.

.PARAMETER Compliance
    Deploy device compliance policies only.

.PARAMETER UpdateRings
    Deploy Windows Update rings only.

.PARAMETER DriverUpdates
    Deploy Driver Update profiles only.

.PARAMETER AppProtection
    Deploy App Protection policies only.

.PARAMETER CAInitialState
    Initial state for Conditional Access policies.
    Default: enabledForReportingButNotEnforced (report-only mode)

.PARAMETER WhatIf
    Preview changes without making them.

.PARAMETER GenerateReport
    Generate deployment report after completion.

.EXAMPLE
    # Deploy all configurations
    ./Deploy-IntuneConfig.ps1 -ConfigPath "./configs" -All

.EXAMPLE
    # Deploy only Conditional Access in report-only mode
    ./Deploy-IntuneConfig.ps1 -ConfigPath "./configs" -ConditionalAccess

.EXAMPLE
    # Preview deployment without making changes
    ./Deploy-IntuneConfig.ps1 -ConfigPath "./configs" -All -WhatIf

.EXAMPLE
    # Deploy CA policies in enabled state (production)
    ./Deploy-IntuneConfig.ps1 -ConfigPath "./configs" -ConditionalAccess -CAInitialState enabled

.NOTES
    Requires Microsoft.Graph PowerShell modules.
    Run Install-Module Microsoft.Graph -Scope CurrentUser to install.
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
    [switch]$Compliance,

    [Parameter(ParameterSetName = 'Selective')]
    [switch]$UpdateRings,

    [Parameter(ParameterSetName = 'Selective')]
    [switch]$DriverUpdates,

    [Parameter(ParameterSetName = 'Selective')]
    [switch]$AppProtection,

    [Parameter()]
    [ValidateSet("enabled", "disabled", "enabledForReportingButNotEnforced")]
    [string]$CAInitialState = "enabledForReportingButNotEnforced",

    [Parameter()]
    [switch]$GenerateReport
)

#region Script Setup

$ErrorActionPreference = 'Stop'
$startTime = Get-Date

# Import module
$modulePath = Join-Path $PSScriptRoot "modules/IntuneDeploy.psm1"
if (-not (Test-Path $modulePath)) {
    Write-Error "Module not found: $modulePath"
    exit 1
}
Import-Module $modulePath -Force

# Results tracking
$results = @{
    StartTime = $startTime
    Groups = @{ Success = 0; Failed = 0; Skipped = 0; Details = @() }
    NamedLocations = @{ Success = 0; Failed = 0; Skipped = 0; Details = @() }
    ConditionalAccess = @{ Success = 0; Failed = 0; Skipped = 0; Details = @() }
    Compliance = @{ Success = 0; Failed = 0; Skipped = 0; Details = @() }
    UpdateRings = @{ Success = 0; Failed = 0; Skipped = 0; Details = @() }
    DriverUpdates = @{ Success = 0; Failed = 0; Skipped = 0; Details = @() }
    AppProtection = @{ Success = 0; Failed = 0; Skipped = 0; Details = @() }
}

#endregion

#region Helper Functions

function Find-ConfigFiles {
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

function Update-Results {
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
    }
}

function Write-DeploymentReport {
    param(
        [hashtable]$Results,
        [string]$OutputPath
    )

    $endTime = Get-Date
    $duration = $endTime - $Results.StartTime

    $report = @"
# Intune Deployment Report
Generated: $($endTime.ToString("yyyy-MM-dd HH:mm:ss")) UTC
Duration: $($duration.ToString("hh\:mm\:ss"))

## Summary

| Category | Success | Failed | Skipped |
|----------|---------|--------|---------|
| Groups | $($Results.Groups.Success) | $($Results.Groups.Failed) | $($Results.Groups.Skipped) |
| Named Locations | $($Results.NamedLocations.Success) | $($Results.NamedLocations.Failed) | $($Results.NamedLocations.Skipped) |
| Conditional Access | $($Results.ConditionalAccess.Success) | $($Results.ConditionalAccess.Failed) | $($Results.ConditionalAccess.Skipped) |
| Compliance | $($Results.Compliance.Success) | $($Results.Compliance.Failed) | $($Results.Compliance.Skipped) |
| Update Rings | $($Results.UpdateRings.Success) | $($Results.UpdateRings.Failed) | $($Results.UpdateRings.Skipped) |
| Driver Updates | $($Results.DriverUpdates.Success) | $($Results.DriverUpdates.Failed) | $($Results.DriverUpdates.Skipped) |
| App Protection | $($Results.AppProtection.Success) | $($Results.AppProtection.Failed) | $($Results.AppProtection.Skipped) |

## Totals
- **Total Deployed**: $(($Results.Groups.Success + $Results.NamedLocations.Success + $Results.ConditionalAccess.Success + $Results.Compliance.Success + $Results.UpdateRings.Success + $Results.DriverUpdates.Success + $Results.AppProtection.Success))
- **Total Failed**: $(($Results.Groups.Failed + $Results.NamedLocations.Failed + $Results.ConditionalAccess.Failed + $Results.Compliance.Failed + $Results.UpdateRings.Failed + $Results.DriverUpdates.Failed + $Results.AppProtection.Failed))

"@

    # Add failure details if any
    $allFailed = @()
    $allFailed += $Results.Groups.Details | Where-Object { $_.Status -eq "Failed" }
    $allFailed += $Results.NamedLocations.Details | Where-Object { $_.Status -eq "Failed" }
    $allFailed += $Results.ConditionalAccess.Details | Where-Object { $_.Status -eq "Failed" }
    $allFailed += $Results.Compliance.Details | Where-Object { $_.Status -eq "Failed" }
    $allFailed += $Results.UpdateRings.Details | Where-Object { $_.Status -eq "Failed" }
    $allFailed += $Results.DriverUpdates.Details | Where-Object { $_.Status -eq "Failed" }
    $allFailed += $Results.AppProtection.Details | Where-Object { $_.Status -eq "Failed" }

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
Write-Host "  Intune Configuration Deployment" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($WhatIfPreference) {
    Write-Host "[WHAT-IF MODE] No changes will be made`n" -ForegroundColor Yellow
}

# Connect to Graph
if (-not (Test-IntuneGraphConnection)) {
    $connected = Connect-IntuneGraph
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
$deployCompliance = $All -or $Compliance
$deployUpdateRings = $All -or $UpdateRings
$deployDriverUpdates = $All -or $DriverUpdates
$deployAppProtection = $All -or $AppProtection

# If no specific flags, default to All
if (-not ($deployGroups -or $deployNamedLocations -or $deployCA -or $deployCompliance -or $deployUpdateRings -or $deployDriverUpdates -or $deployAppProtection)) {
    Write-Warning "No deployment type specified. Use -All or specific flags."
    exit 0
}

#region Deploy Groups (Dependency for CA)
if ($deployGroups) {
    Write-Host "=== Deploying Groups ===" -ForegroundColor Magenta

    $groupFiles = Find-ConfigFiles -BasePath $ConfigPath -SearchPaths @(
        "Groups",
        "Source/ConditionalAccessBaseline-main/Config/Groups"
    )

    if ($groupFiles.Count -eq 0) {
        Write-Host "  No group configuration files found" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Found $($groupFiles.Count) group configuration(s)" -ForegroundColor Cyan

        foreach ($file in $groupFiles) {
            try {
                $config = Read-ConfigurationFile -Path $file.FullName
                $result = Deploy-EntraGroup -Configuration $config -WhatIf:$WhatIfPreference
                Update-Results -CategoryResults $results.Groups -DeployResult $result -Name $config.displayName
            }
            catch {
                Write-Error "Error processing $($file.Name): $_"
                Update-Results -CategoryResults $results.Groups -DeployResult @{ Status = "Failed"; Error = $_.Exception.Message } -Name $file.Name
            }
        }
    }
    Write-Host ""
}
#endregion

#region Deploy Named Locations (Dependency for CA)
if ($deployNamedLocations) {
    Write-Host "=== Deploying Named Locations ===" -ForegroundColor Magenta

    $locationFiles = Find-ConfigFiles -BasePath $ConfigPath -SearchPaths @(
        "NamedLocations",
        "Source/ConditionalAccessBaseline-main/Config/NamedLocations"
    )

    if ($locationFiles.Count -eq 0) {
        Write-Host "  No named location configuration files found" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Found $($locationFiles.Count) named location configuration(s)" -ForegroundColor Cyan

        foreach ($file in $locationFiles) {
            try {
                $config = Read-ConfigurationFile -Path $file.FullName
                $result = Deploy-NamedLocation -Configuration $config -WhatIf:$WhatIfPreference
                Update-Results -CategoryResults $results.NamedLocations -DeployResult $result -Name $config.displayName
            }
            catch {
                Write-Error "Error processing $($file.Name): $_"
                Update-Results -CategoryResults $results.NamedLocations -DeployResult @{ Status = "Failed"; Error = $_.Exception.Message } -Name $file.Name
            }
        }
    }
    Write-Host ""
}
#endregion

#region Deploy Conditional Access Policies
if ($deployCA) {
    Write-Host "=== Deploying Conditional Access Policies ===" -ForegroundColor Magenta
    Write-Host "  Initial state: $CAInitialState" -ForegroundColor Cyan

    $caFiles = Find-ConfigFiles -BasePath $ConfigPath -SearchPaths @(
        "ConditionalAccess",
        "Conditonal access policies/ConditionalAccess"
    )

    if ($caFiles.Count -eq 0) {
        Write-Host "  No Conditional Access configuration files found" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Found $($caFiles.Count) CA policy configuration(s)" -ForegroundColor Cyan

        foreach ($file in $caFiles) {
            try {
                $config = Read-ConfigurationFile -Path $file.FullName
                $result = Deploy-ConditionalAccessPolicy -Configuration $config -InitialState $CAInitialState -WhatIf:$WhatIfPreference
                Update-Results -CategoryResults $results.ConditionalAccess -DeployResult $result -Name $config.displayName
            }
            catch {
                Write-Error "Error processing $($file.Name): $_"
                Update-Results -CategoryResults $results.ConditionalAccess -DeployResult @{ Status = "Failed"; Error = $_.Exception.Message } -Name $file.Name
            }
        }
    }
    Write-Host ""
}
#endregion

#region Deploy Compliance Policies
if ($deployCompliance) {
    Write-Host "=== Deploying Compliance Policies ===" -ForegroundColor Magenta

    $complianceFiles = Find-ConfigFiles -BasePath $ConfigPath -SearchPaths @(
        "WINDOWS/CompliancePolicies",
        "W365/CompliancePolicies",
        "macOS/CompliancePolicies",
        "CompliancePolicies"
    )

    if ($complianceFiles.Count -eq 0) {
        Write-Host "  No compliance policy configuration files found" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Found $($complianceFiles.Count) compliance policy configuration(s)" -ForegroundColor Cyan

        foreach ($file in $complianceFiles) {
            try {
                $config = Read-ConfigurationFile -Path $file.FullName
                $result = Deploy-CompliancePolicy -Configuration $config -WhatIf:$WhatIfPreference
                Update-Results -CategoryResults $results.Compliance -DeployResult $result -Name $config.displayName
            }
            catch {
                Write-Error "Error processing $($file.Name): $_"
                Update-Results -CategoryResults $results.Compliance -DeployResult @{ Status = "Failed"; Error = $_.Exception.Message } -Name $file.Name
            }
        }
    }
    Write-Host ""
}
#endregion

#region Deploy Update Rings
if ($deployUpdateRings) {
    Write-Host "=== Deploying Windows Update Rings ===" -ForegroundColor Magenta

    $updateFiles = Find-ConfigFiles -BasePath $ConfigPath -SearchPaths @(
        "WINDOWS/WindowsUpdateRings",
        "WindowsUpdateRings"
    )

    if ($updateFiles.Count -eq 0) {
        Write-Host "  No update ring configuration files found" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Found $($updateFiles.Count) update ring configuration(s)" -ForegroundColor Cyan

        foreach ($file in $updateFiles) {
            try {
                $config = Read-ConfigurationFile -Path $file.FullName
                $result = Deploy-WindowsUpdateRing -Configuration $config -WhatIf:$WhatIfPreference
                Update-Results -CategoryResults $results.UpdateRings -DeployResult $result -Name $config.displayName
            }
            catch {
                Write-Error "Error processing $($file.Name): $_"
                Update-Results -CategoryResults $results.UpdateRings -DeployResult @{ Status = "Failed"; Error = $_.Exception.Message } -Name $file.Name
            }
        }
    }
    Write-Host ""
}
#endregion

#region Deploy Driver Updates
if ($deployDriverUpdates) {
    Write-Host "=== Deploying Driver Update Profiles ===" -ForegroundColor Magenta

    $driverFiles = Find-ConfigFiles -BasePath $ConfigPath -SearchPaths @(
        "WINDOWS/DriverUpdateRings",
        "DriverUpdateRings"
    )

    if ($driverFiles.Count -eq 0) {
        Write-Host "  No driver update configuration files found" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Found $($driverFiles.Count) driver update configuration(s)" -ForegroundColor Cyan

        foreach ($file in $driverFiles) {
            try {
                $config = Read-ConfigurationFile -Path $file.FullName
                $result = Deploy-DriverUpdateProfile -Configuration $config -WhatIf:$WhatIfPreference
                Update-Results -CategoryResults $results.DriverUpdates -DeployResult $result -Name $config.displayName
            }
            catch {
                Write-Error "Error processing $($file.Name): $_"
                Update-Results -CategoryResults $results.DriverUpdates -DeployResult @{ Status = "Failed"; Error = $_.Exception.Message } -Name $file.Name
            }
        }
    }
    Write-Host ""
}
#endregion

#region Deploy App Protection Policies
if ($deployAppProtection) {
    Write-Host "=== Deploying App Protection Policies ===" -ForegroundColor Magenta

    $appFiles = Find-ConfigFiles -BasePath $ConfigPath -SearchPaths @(
        "BYOD",
        "AppProtection",
        "MAM"
    )

    if ($appFiles.Count -eq 0) {
        Write-Host "  No app protection configuration files found" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Found $($appFiles.Count) app protection configuration(s)" -ForegroundColor Cyan

        foreach ($file in $appFiles) {
            try {
                $config = Read-ConfigurationFile -Path $file.FullName
                $result = Deploy-AppProtectionPolicy -Configuration $config -WhatIf:$WhatIfPreference
                Update-Results -CategoryResults $results.AppProtection -DeployResult $result -Name $config.displayName
            }
            catch {
                Write-Error "Error processing $($file.Name): $_"
                Update-Results -CategoryResults $results.AppProtection -DeployResult @{ Status = "Failed"; Error = $_.Exception.Message } -Name $file.Name
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

$totalSuccess = $results.Groups.Success + $results.NamedLocations.Success + $results.ConditionalAccess.Success + $results.Compliance.Success + $results.UpdateRings.Success + $results.DriverUpdates.Success + $results.AppProtection.Success
$totalFailed = $results.Groups.Failed + $results.NamedLocations.Failed + $results.ConditionalAccess.Failed + $results.Compliance.Failed + $results.UpdateRings.Failed + $results.DriverUpdates.Failed + $results.AppProtection.Failed

Write-Host "Total Deployed: $totalSuccess" -ForegroundColor Green
Write-Host "Total Failed: $totalFailed" -ForegroundColor $(if ($totalFailed -gt 0) { "Red" } else { "Green" })

if ($GenerateReport) {
    $reportPath = Join-Path $PSScriptRoot "deployment-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
    Write-DeploymentReport -Results $results -OutputPath $reportPath
}

# Exit with error code if failures
if ($totalFailed -gt 0) {
    exit 1
}

#endregion

#endregion
