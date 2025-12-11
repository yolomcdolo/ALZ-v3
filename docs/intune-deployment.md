# Intune Deployment Guide

## Overview

ALZ-v3 includes an Intune Council - a collection of AI agents and PowerShell scripts designed to deploy Microsoft Intune configurations and Conditional Access policies using the Microsoft Graph API.

## Quick Start

### Prerequisites

1. **PowerShell 7.0+**
   ```powershell
   winget install Microsoft.PowerShell
   ```

2. **Microsoft.Graph PowerShell SDK**
   ```powershell
   Install-Module Microsoft.Graph -Scope CurrentUser
   ```

3. **Required Permissions** (Entra ID)
   - `Group.ReadWrite.All` - Create/manage security groups
   - `Policy.ReadWrite.ConditionalAccess` - Manage CA policies
   - `DeviceManagementConfiguration.ReadWrite.All` - Manage device configs
   - `DeviceManagementApps.ReadWrite.All` - Manage app protection

### Local Deployment

```powershell
# Navigate to scripts directory
cd ALZ-v3/scripts/intune

# Deploy all configurations
./Deploy-IntuneConfig.ps1 -ConfigPath "path/to/configs" -All

# Deploy specific types
./Deploy-IntuneConfig.ps1 -ConfigPath "path/to/configs" -ConditionalAccess
./Deploy-IntuneConfig.ps1 -ConfigPath "path/to/configs" -Compliance

# Preview changes (What-If mode)
./Deploy-IntuneConfig.ps1 -ConfigPath "path/to/configs" -All -WhatIf
```

## Configuration Structure

Organize your configuration files in this directory structure:

```
intune-configs/
├── Groups/                          # Entra ID security groups
│   ├── CA-Exclusion-EmergencyAccess.json
│   └── CA-Exclusion-ServiceAccounts.json
├── NamedLocations/                  # Named locations for CA
│   └── Corporate-Network.json
├── ConditionalAccess/               # CA policies
│   ├── CA001-Block-Legacy-Auth.json
│   └── CA002-Require-MFA.json
├── WINDOWS/
│   ├── CompliancePolicies/          # Windows compliance
│   │   └── WIN-Compliance-Baseline.json
│   ├── WindowsUpdateRings/          # WUfB rings
│   │   └── WUfB-Ring-Pilot.json
│   └── DriverUpdateRings/           # Driver updates
│       └── Driver-Ring-Pilot.json
├── BYOD/                            # App protection (MAM)
│   ├── iOS-MAM-Corporate.json
│   └── Android-MAM-Corporate.json
└── W365/
    └── CompliancePolicies/          # Windows 365 specific
        └── W365-Compliance.json
```

## Deployment Order

The deployment script respects dependencies:

```
1. Groups           ← Base dependency (CA exclusions)
2. Named Locations  ← Geo-based CA policies
3. Conditional Access ← Depends on Groups & Locations
4. Compliance       ← Can reference CA for remediation
5. Update Rings     ← Independent
6. App Protection   ← Independent
```

## Configuration Examples

### Security Group (CA Exclusion)

```json
{
    "displayName": "CA-Exclusion-EmergencyAccess",
    "description": "Emergency access accounts excluded from Conditional Access policies",
    "mailEnabled": false,
    "securityEnabled": true
}
```

### Conditional Access Policy

```json
{
    "displayName": "CA001-Block-Legacy-Auth",
    "state": "enabledForReportingButNotEnforced",
    "conditions": {
        "users": {
            "includeUsers": ["All"],
            "excludeGroups": ["{{GroupId:CA-Exclusion-EmergencyAccess}}"]
        },
        "applications": {
            "includeApplications": ["All"]
        },
        "clientAppTypes": ["exchangeActiveSync", "other"]
    },
    "grantControls": {
        "operator": "OR",
        "builtInControls": ["block"]
    }
}
```

Note: `{{GroupId:name}}` placeholders are automatically resolved during deployment.

### Windows Compliance Policy

```json
{
    "@odata.type": "#microsoft.graph.windows10CompliancePolicy",
    "displayName": "WIN-Compliance-Baseline",
    "description": "Windows 10/11 security baseline",
    "passwordRequired": true,
    "passwordMinimumLength": 12,
    "bitLockerEnabled": true,
    "secureBootEnabled": true,
    "defenderEnabled": true
}
```

### Windows Update Ring

```json
{
    "@odata.type": "#microsoft.graph.windowsUpdateForBusinessConfiguration",
    "displayName": "WUfB-Ring-Pilot",
    "description": "Pilot ring for early adopters",
    "qualityUpdatesDeferralPeriodInDays": 0,
    "featureUpdatesDeferralPeriodInDays": 0,
    "automaticUpdateMode": "autoInstallAtMaintenanceTime"
}
```

### App Protection Policy (iOS)

```json
{
    "@odata.type": "#microsoft.graph.iosManagedAppProtection",
    "displayName": "iOS-MAM-Corporate",
    "description": "Corporate data protection for iOS",
    "pinRequired": true,
    "minimumPinLength": 6,
    "dataBackupBlocked": true,
    "allowedOutboundDataTransferDestinations": "managedApps",
    "allowedInboundDataTransferSources": "managedApps"
}
```

## CI/CD Deployment

### GitHub Actions

The repository includes two workflows:

1. **validate-intune-config.yml** - Validates JSON files on push/PR
2. **deploy-intune.yml** - Deploys configurations (manual trigger)

### Required Secrets

Configure these in your GitHub repository:

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | App registration client ID |
| `AZURE_TENANT_ID` | Entra ID tenant ID |

### GitHub Environments

Create environments for staged deployments:
- `dev` - Development/testing
- `staging` - Pre-production validation
- `prod` - Production (requires approval)

### Triggering Deployment

1. Go to **Actions** > **Deploy Intune Configuration**
2. Click **Run workflow**
3. Select:
   - Environment (dev/staging/prod)
   - Deployment type (all/specific)
   - CA initial state (report-only recommended)
   - What-If mode (for preview)
4. Click **Run workflow**

## Conditional Access Rollout Strategy

### Recommended Approach

1. **Deploy in Report-Only Mode**
   ```powershell
   ./Deploy-IntuneConfig.ps1 -ConfigPath "./configs" -ConditionalAccess -CAInitialState enabledForReportingButNotEnforced
   ```

2. **Monitor Sign-In Logs** (1-2 weeks)
   - Review Azure AD Sign-in logs
   - Check "Report-only" column for policy impact
   - Identify potential lockouts

3. **Enable for Pilot Group**
   - Modify policy to target pilot group
   - Monitor for issues

4. **Enable for All Users**
   ```powershell
   ./Deploy-IntuneConfig.ps1 -ConfigPath "./configs" -ConditionalAccess -CAInitialState enabled
   ```

## Troubleshooting

### Authentication Issues

**Problem**: `Connect-MgGraph` fails

**Solution**:
```powershell
# Clear cached tokens
Disconnect-MgGraph
# Re-authenticate
Connect-MgGraph -Scopes "Group.ReadWrite.All","Policy.ReadWrite.ConditionalAccess"
```

### Permission Denied

**Problem**: `Insufficient privileges to complete the operation`

**Solution**:
1. Verify app registration has required API permissions
2. Ensure admin consent is granted
3. Check if user has required Entra ID roles

### Policy Not Updating

**Problem**: Changes not reflected after deployment

**Solution**:
1. Check for policy with same displayName
2. Verify no conflicting policies
3. Wait for Azure AD replication (up to 15 minutes)

### UTF-16 Encoding Issues

**Problem**: JSON parsing errors with exported configs

**Solution**: The module automatically handles UTF-16 encoded files from Microsoft Graph exports.

## Agent Architecture

The Intune Council consists of 7 specialized agents:

| Agent | Responsibility |
|-------|---------------|
| intune-council-chair | Orchestration and dependency management |
| identity-manager | Groups and Named Locations |
| compliance-deployer | Device compliance policies |
| update-manager | Windows Update and Driver rings |
| app-protection | App Protection Policies (MAM) |
| conditional-access-deployer | Conditional Access policies |
| intune-deployment-tester | Validation and reporting |

See `agents/intune-council/README.md` for detailed architecture.

## Best Practices

1. **Always use Report-Only first** for CA policies
2. **Maintain emergency access accounts** excluded from all policies
3. **Version control configurations** in Git
4. **Test in dev environment** before production
5. **Document policy changes** with meaningful displayNames
6. **Regular compliance reviews** to verify policy effectiveness

## References

- [Microsoft Graph API - Intune](https://docs.microsoft.com/graph/api/resources/intune-graph-overview)
- [Conditional Access API](https://docs.microsoft.com/graph/api/resources/conditionalaccesspolicy)
- [Microsoft.Graph PowerShell](https://docs.microsoft.com/powershell/microsoftgraph/)
- [Intune Device Compliance](https://docs.microsoft.com/mem/intune/protect/device-compliance-get-started)
