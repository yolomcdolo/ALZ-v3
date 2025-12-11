# IAM Configuration Files

This directory contains Identity and Access Management (IAM) configuration files for secure deployment to Microsoft Entra ID.

## SECURITY NOTICE

These configurations control authentication and authorization to your Microsoft tenant. Handle with extreme care:

- **Never commit secrets or credentials** to this repository
- **Always use report-only mode first** for Conditional Access policies
- **Maintain break-glass account exclusions** in all CA policies
- **Review all changes** before deploying to production

## Directory Structure

```
iam-configs/
├── Groups/                    # Entra ID security groups
│   ├── CA-Exclusion-EmergencyAccess.json
│   ├── CA-Exclusion-BreakGlass.json
│   └── CA-Exclusion-ServiceAccounts.json
├── NamedLocations/           # Trusted network locations
│   ├── Corporate-Network.json
│   └── Trusted-VPN.json
├── ConditionalAccess/        # CA policies
│   ├── CA001-Block-Legacy-Auth.json
│   ├── CA002-Require-MFA-AllUsers.json
│   └── CA003-Block-HighRisk-Countries.json
├── ServicePrincipals/        # App registrations
│   └── sp-automation.json
└── SSO/                      # SSO integrations
    ├── saml-app.json
    └── oidc-app.json
```

## Deployment Order (CRITICAL)

IAM configurations have dependencies that MUST be respected:

1. **Groups** - Create exclusion groups first (CA dependencies)
2. **Named Locations** - Create trusted locations (CA dependencies)
3. **Conditional Access** - Deploy policies with dependencies resolved
4. **Service Principals** - Optional, for automation
5. **SSO Integrations** - Optional, for enterprise apps

## Placeholder Resolution

Use placeholders in CA policies that get resolved at deployment time:

- `{{GroupId:DisplayName}}` - Resolves to the Object ID of the group
- `{{NamedLocationId:DisplayName}}` - Resolves to the ID of the named location

Example:
```json
{
    "excludeGroups": ["{{GroupId:CA-Exclusion-EmergencyAccess}}"]
}
```

## Break-Glass Requirements

**ALL Conditional Access policies MUST exclude break-glass accounts.**

The deployment script validates that:
1. A break-glass exclusion group exists
2. All CA policies exclude at least one break-glass group
3. Break-glass accounts are never targeted by blocking policies

## Deployment

```powershell
# Development (auto-approve)
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -Environment dev -All

# Production (report-only mode enforced)
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -Environment prod -All

# Preview only (no changes)
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -All -WhatIf
```

## Environment Approval Requirements

| Environment | Approval | CA Initial State |
|-------------|----------|------------------|
| dev | Auto | User choice |
| staging | Single approver | Report-only recommended |
| prod | 2+ approvers | Report-only enforced |

See `docs/iam-deployment.md` for complete documentation.
