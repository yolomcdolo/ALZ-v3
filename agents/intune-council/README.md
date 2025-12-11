# Intune Council - AI Agent Architecture

## Overview

The Intune Council is a specialized team of AI agents designed to deploy Microsoft Intune configurations and Conditional Access policies through the Microsoft Graph API.

## Agent Architecture

```
                    ┌─────────────────────────────┐
                    │   intune-council-chair      │
                    │   Master Orchestrator       │
                    └──────────────┬──────────────┘
                                   │
       ┌───────────────┬───────────┼───────────────┬───────────────┐
       │               │           │               │               │
       ▼               ▼           ▼               ▼               ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│  identity-  │ │ compliance- │ │  update-    │ │   app-      │ │conditional- │
│   manager   │ │  deployer   │ │  manager    │ │ protection  │ │   access    │
│             │ │             │ │             │ │             │ │  deployer   │
│ Groups,     │ │ Device &    │ │ Windows &   │ │ iOS/Android │ │ CA Policies │
│ Named Locs  │ │ Compliance  │ │ Driver Upd  │ │ MAM/BYOD    │ │ & Sessions  │
└─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘
       │               │           │               │               │
       └───────────────┴───────────┴───────────────┴───────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │   intune-deployment-tester  │
                    │   Validation & Reporting    │
                    └─────────────────────────────┘
```

## Agent Descriptions

| Agent | Purpose | Graph API Scope |
|-------|---------|-----------------|
| intune-council-chair | Orchestrates deployment workflow, manages dependencies | All |
| identity-manager | Deploys Entra ID groups and Named Locations | Group.ReadWrite.All, Policy.Read.All |
| compliance-deployer | Deploys device compliance policies | DeviceManagementConfiguration.ReadWrite.All |
| update-manager | Deploys Windows Update and Driver Update rings | DeviceManagementConfiguration.ReadWrite.All |
| app-protection | Deploys App Protection Policies (MAM) | DeviceManagementApps.ReadWrite.All |
| conditional-access-deployer | Deploys Conditional Access policies | Policy.ReadWrite.ConditionalAccess |
| intune-deployment-tester | Validates deployments and generates reports | Read-only scopes |

## Dependency Chain

Deployments must follow this order to satisfy dependencies:

```
1. Groups (Entra ID)           ← Base dependency for CA exclusions
2. Named Locations             ← Geo-based CA policies
3. Conditional Access Policies ← Depends on Groups & Named Locations
4. Compliance Policies         ← Can reference CA for remediation
5. Update Rings                ← Independent, can deploy in parallel
6. App Protection              ← Independent, can deploy in parallel
```

## Authentication

Interactive user login per terminal session using Microsoft.Graph SDK:

```powershell
Connect-MgGraph -Scopes @(
    "Group.ReadWrite.All",
    "Policy.ReadWrite.ConditionalAccess",
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementApps.ReadWrite.All"
)
```

## Usage

### Full Deployment
```powershell
./scripts/intune/Deploy-IntuneConfig.ps1 -ConfigPath "path/to/configs" -All
```

### Selective Deployment
```powershell
# Deploy only Conditional Access
./scripts/intune/Deploy-IntuneConfig.ps1 -ConfigPath "path/to/configs" -ConditionalAccess

# Deploy only Compliance Policies
./scripts/intune/Deploy-IntuneConfig.ps1 -ConfigPath "path/to/configs" -Compliance
```

### What-If Mode
```powershell
./scripts/intune/Deploy-IntuneConfig.ps1 -ConfigPath "path/to/configs" -All -WhatIf
```

## Configuration Sources

Configurations are exported from Microsoft Graph API in JSON format:

| Type | Location | Count |
|------|----------|-------|
| Windows Compliance | WINDOWS/CompliancePolicies/ | 8 |
| Windows Update Rings | WINDOWS/WindowsUpdateRings/ | 3 |
| Driver Update Rings | WINDOWS/DriverUpdateRings/ | 3 |
| Conditional Access | ConditionalAccess/ | 23 |
| App Protection (BYOD) | BYOD/ | 2 |
| W365 Compliance | W365/CompliancePolicies/ | 1 |
| Entra ID Groups | Groups/ | 34 |
| Named Locations | NamedLocations/ | 1 |

## CI/CD Integration

GitHub Actions workflow available at `.github/workflows/deploy-intune.yml`

Supports:
- Manual deployment triggers
- Environment-based deployment (dev/staging/prod)
- What-if dry runs
- Deployment validation and reporting
