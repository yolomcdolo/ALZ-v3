# IAM Council Deployment Guide

Comprehensive guide for deploying Identity and Access Management configurations using the IAM Council.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Configuration Structure](#configuration-structure)
4. [Deployment Workflows](#deployment-workflows)
5. [Security Features](#security-features)
6. [Approval Gates](#approval-gates)
7. [Monitoring & Validation](#monitoring--validation)
8. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Software

- PowerShell 7.0 or later
- Microsoft.Graph PowerShell SDK:
  ```powershell
  Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
  Install-Module Microsoft.Graph.Groups -Scope CurrentUser
  Install-Module Microsoft.Graph.Identity.SignIns -Scope CurrentUser
  Install-Module Microsoft.Graph.Applications -Scope CurrentUser
  ```

### Required Permissions

#### Interactive User Deployment
- Global Administrator OR
- Conditional Access Administrator + Groups Administrator

#### GitHub Actions (CI/CD)
- Azure OIDC Federated Credentials configured
- Service Principal with permissions:
  - `Group.ReadWrite.All`
  - `Policy.ReadWrite.ConditionalAccess`
  - `Application.ReadWrite.All`
  - `Directory.ReadWrite.All`

### Break-Glass Accounts

**CRITICAL**: Configure break-glass accounts BEFORE deploying Conditional Access policies.

Requirements:
- Minimum 2 break-glass accounts
- Cloud-only accounts (not synced from on-premises)
- FIDO2 security keys recommended (no passwords)
- Excluded from ALL Conditional Access policies
- Monitored with real-time alerts

## Quick Start

### 1. Create IAM Configs Directory

```bash
cd C:/Users/John/ALZ-v3

# Create directory structure
mkdir -p iam-configs/{Groups,NamedLocations,ConditionalAccess,ServicePrincipals,SSO}
```

### 2. Add Break-Glass Groups (FIRST)

Create `iam-configs/Groups/CA-Exclusion-EmergencyAccess.json`:

```json
{
  "displayName": "CA-Exclusion-EmergencyAccess",
  "description": "Emergency access accounts excluded from ALL Conditional Access policies. Monitor all sign-ins.",
  "mailEnabled": false,
  "mailNickname": "ca-exclusion-emergency",
  "securityEnabled": true,
  "groupTypes": []
}
```

### 3. Deploy Break-Glass Groups

```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Group.ReadWrite.All", "Policy.ReadWrite.ConditionalAccess"

# Deploy groups FIRST
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -Groups -Environment dev
```

### 4. Add Conditional Access Policies

Create `iam-configs/ConditionalAccess/CA001-Block-Legacy-Auth.json`:

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

### 5. Deploy Conditional Access Policies

```powershell
# Deploy CA policies in report-only mode
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -ConditionalAccess -Environment dev
```

## Configuration Structure

```
iam-configs/
├── Groups/                              # Entra ID security groups
│   ├── CA-Exclusion-EmergencyAccess.json
│   ├── CA-Exclusion-BreakGlass.json
│   ├── CA-Exclusion-ServiceAccounts.json
│   └── CA-Pilot-Users.json
├── NamedLocations/                      # Trusted locations
│   ├── Corporate-Network.json
│   ├── Allowed-Countries.json
│   └── HighRisk-Countries.json
├── ConditionalAccess/                   # CA policies
│   ├── CA001-Block-Legacy-Auth.json
│   ├── CA002-Require-MFA-AllUsers.json
│   ├── CA003-Block-HighRisk-Countries.json
│   ├── CA004-Require-Compliant-Device.json
│   └── CA005-Require-PhishingResistant-MFA-Admins.json
├── ServicePrincipals/                   # App registrations
│   └── sp-automation-prod.json
└── SSO/                                 # SSO integrations
    ├── saml-app1.json
    └── oidc-app2.json
```

## Deployment Workflows

### Development Environment

```powershell
# Full deployment (auto-approve, no gates)
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -All -Environment dev

# What-If mode (preview changes)
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -All -Environment dev -WhatIf

# Selective deployment
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -ConditionalAccess -Environment dev
```

### Staging Environment

```powershell
# Requires single approver (configured in GitHub Actions)
# Use GitHub Actions workflow instead of local deployment
```

### Production Environment

```powershell
# Requires 2+ approvers (configured in GitHub Actions)
# CA policies ALWAYS deploy in report-only mode initially
# Use GitHub Actions workflow instead of local deployment
```

### GitHub Actions Deployment

1. Go to GitHub → Actions → Deploy IAM Configuration
2. Click "Run workflow"
3. Select environment: `prod`
4. Select deployment type: `conditional-access`
5. Set CA initial state: `enabledForReportingButNotEnforced`
6. Enable What-If: `false`
7. Click "Run workflow"
8. Await approval from 2+ approvers
9. Monitor deployment progress
10. Review deployment report in Artifacts

## Security Features

### 1. Break-Glass Protection

**Mandatory for ALL CA policies**:

```json
{
  "conditions": {
    "users": {
      "excludeGroups": [
        "{{GroupId:CA-Exclusion-EmergencyAccess}}",
        "{{GroupId:CA-Exclusion-BreakGlass}}"
      ]
    }
  }
}
```

**Validation**:
- Pre-deployment validation enforces break-glass exclusions
- Deployment fails if missing
- Post-deployment testing verifies break-glass accessibility

### 2. Report-Only Mode Enforcement

**Production CA policies MUST start in report-only mode**:

```json
{
  "state": "enabledForReportingButNotEnforced"
}
```

**Enforcement**:
- Deployment script blocks `enabled` state in production
- GitHub Actions workflow validates CA state
- Manual override not possible

**Rollout Process**:
1. Deploy in report-only mode (Week 1-2)
2. Monitor sign-in logs daily
3. Analyze What-If impact
4. Enable for pilot group (Week 3)
5. Enable for all users (Week 4+)

### 3. Audit Logging

All IAM changes logged to `scripts/iam/logs/iam-audit.log`:

```json
{
  "timestamp": "2025-12-11T14:30:22Z",
  "action": "CAPolicyCreated",
  "operator": "admin@company.com",
  "tenantId": "00000000-0000-0000-0000-000000000000",
  "resourceName": "CA001-Block-Legacy-Auth",
  "resourceId": "policy-id",
  "severity": "Critical"
}
```

### 4. Automatic Backups

Before every deployment:
- Full configuration snapshot
- Policy state preservation
- Stored in `scripts/iam/backups/ca-policies/`
- 90-day retention
- One-click rollback

### 5. Placeholder Resolution

Automatic object ID resolution:

```json
// Before deployment
"excludeGroups": ["{{GroupId:CA-Exclusion-EmergencyAccess}}"]

// After resolution
"excludeGroups": ["00000000-0000-0000-0000-000000000001"]
```

## Approval Gates

### Development
- **Approvers**: None (auto-approve)
- **Deployment**: Immediate
- **Use Case**: Testing, validation

### Staging
- **Approvers**: 1 required
- **Approval Window**: 24 hours
- **Use Case**: Pre-production validation

### Production
- **Approvers**: 2+ required (multi-approval)
- **Approval Window**: 4 hours
- **Use Case**: Production deployments only
- **Additional Requirements**:
  - What-If analysis mandatory
  - Sign-in log review (for CA policy enablement)
  - Rollback plan documented

## Monitoring & Validation

### Post-Deployment Validation

```powershell
# 1. Verify break-glass accessibility
Test-BreakGlassAccountAccess -Accounts @("breakglass1@domain.com", "breakglass2@domain.com")

# 2. Review sign-in logs
Get-MgAuditLogSignIn -Filter "createdDateTime ge $((Get-Date).AddHours(-1).ToString('o'))"

# 3. Check CA policy evaluation
Get-MgIdentityConditionalAccessPolicy | Select-Object DisplayName, State

# 4. Review audit logs
Get-Content scripts/iam/logs/iam-audit.log -Tail 50
```

### What-If Analysis

```powershell
# Analyze policy impact before enabling
Invoke-ConditionalAccessWhatIf -PolicyId $policyId -UserUpn "testuser@company.com"
```

### Sign-In Log Analysis

```powershell
# Review sign-ins affected by report-only policy
$signIns = Get-MgAuditLogSignIn -Filter "conditionalAccessStatus eq 'reportOnlySuccess' or conditionalAccessStatus eq 'reportOnlyFailure'"

# Analyze impact
$impactAnalysis = Analyze-ReportOnlyPolicyImpact -PolicyName "CA001-Block-Legacy-Auth" -Days 14
```

## Troubleshooting

### Common Issues

#### Issue: "Group not found in mapping"

**Solution**:
```powershell
# Deploy groups BEFORE CA policies
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -Groups -Environment prod
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -ConditionalAccess -Environment prod
```

#### Issue: "Break-glass exclusion missing"

**Solution**:
Add to policy JSON:
```json
{
  "conditions": {
    "users": {
      "excludeGroups": ["{{GroupId:CA-Exclusion-EmergencyAccess}}"]
    }
  }
}
```

#### Issue: "Production deployment blocked"

**Solution**:
Ensure CA initial state is report-only:
```powershell
./scripts/iam/Deploy-IAMConfig.ps1 -CAInitialState "enabledForReportingButNotEnforced"
```

### Rollback Procedures

```powershell
# List recent deployments
Get-ChildItem scripts/iam/backups/ca-policies/ | Sort-Object LastWriteTime -Descending

# Rollback to specific backup
Rollback-IAMDeployment -BackupId "20251211-143022"

# Emergency: Disable all CA policies
Disable-AllConditionalAccessPolicies -EmergencyMode -Confirm
```

## Best Practices

1. **Always deploy groups first** (dependencies for CA)
2. **Use report-only mode** in production (mandatory)
3. **Monitor sign-in logs** for 1-2 weeks before enabling
4. **Test break-glass accessibility** after every deployment
5. **Use pilot groups** for high-risk policies
6. **Document policy purpose** and ownership
7. **Review policies quarterly** for effectiveness
8. **Test rollback procedures** regularly
9. **Alert on policy modifications** outside CI/CD
10. **Maintain compliance reports** monthly

## Security Checklist

Before production deployment:

- [ ] Break-glass accounts configured and tested
- [ ] Break-glass exclusions in ALL CA policies
- [ ] Report-only mode for all new CA policies
- [ ] What-If impact analysis completed
- [ ] Sign-in log monitoring configured
- [ ] Audit logging enabled
- [ ] Approval gates configured (2+ approvers)
- [ ] Rollback procedures documented and tested
- [ ] Incident response plan documented
- [ ] Security team notified of deployment

## Support

- **Agent Documentation**: `agents/iam-council/`
- **Audit Logs**: `scripts/iam/logs/iam-audit.log`
- **Deployment Reports**: `scripts/iam/deployment-report-*.md`
- **Migration Guide**: `docs/iam-migration-guide.md`

## References

- [Microsoft Entra Conditional Access Best Practices](https://learn.microsoft.com/en-us/entra/identity/conditional-access/plan-conditional-access)
- [PIM API Documentation](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-apis)
- [Break-Glass Account Management](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access)
- [Secure Best Practices for Entra ID](https://learn.microsoft.com/en-us/entra/architecture/secure-best-practices)
