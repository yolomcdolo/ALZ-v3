# Intune Configuration Files

This directory contains Microsoft Intune and Conditional Access configuration files for deployment.

## Directory Structure

```
intune-configs/
├── Groups/                 # Entra ID security groups (CA exclusions)
├── NamedLocations/         # Trusted locations for CA policies
├── ConditionalAccess/      # Conditional Access policies
├── WINDOWS/
│   ├── CompliancePolicies/ # Windows device compliance
│   └── WindowsUpdateRings/ # Windows Update for Business rings
└── BYOD/                   # App Protection Policies (MAM)
```

## Adding Your Configurations

### Option 1: Export from Existing Tenant

Use Microsoft Graph Explorer or PowerShell to export existing configurations:

```powershell
# Export Conditional Access policies
$policies = Get-MgIdentityConditionalAccessPolicy
foreach ($policy in $policies) {
    $policy | ConvertTo-Json -Depth 10 | Out-File "./ConditionalAccess/$($policy.displayName).json"
}
```

### Option 2: Copy from Source Directory

Copy configurations from your source location:

```powershell
# Copy from existing config folder
Copy-Item -Path "E:\path\to\Intune Config final\*" -Destination "./intune-configs/" -Recurse
```

### Option 3: Create from Templates

Use the example files in this directory as templates for new configurations.

## File Format

All configuration files must be valid JSON. Files exported from Microsoft Graph (UTF-16 encoded) are automatically handled by the deployment scripts.

## Deployment

See `docs/intune-deployment.md` for deployment instructions.

```powershell
# Deploy all configurations
./scripts/intune/Deploy-IntuneConfig.ps1 -ConfigPath "./intune-configs" -All -WhatIf
```
