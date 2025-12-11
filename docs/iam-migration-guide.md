# IAM Council Migration Guide

This guide documents the migration of Conditional Access and identity management components from the Intune Council to the new dedicated IAM Council.

## Executive Summary

**What Changed**: Conditional Access policies, Entra ID groups, Named Locations, and Service Principal management have been separated from the Intune Council into a new security-first IAM Council.

**Why**: To provide specialized, security-focused management of identity and access configurations with enhanced approval workflows, break-glass protection, and audit logging.

**When**: Effective immediately for new deployments. Existing deployments can be migrated using this guide.

## Architectural Changes

### Before (Intune Council)
```
Intune Council
├── identity-manager (Groups, Named Locations)
├── conditional-access-deployer (CA Policies)
├── compliance-deployer (Device Compliance)
├── update-manager (Windows Updates)
└── app-protection (MAM Policies)
```

### After (Separated Councils)
```
IAM Council (NEW - Identity & Access Management)
├── identity-manager (Groups, Named Locations)
├── conditional-access-deployer (CA Policies)
├── service-principal-manager (App Registrations)
├── sso-integrator (SAML/OIDC)
├── iam-security-auditor (Compliance & Audit)
└── iam-deployment-tester (What-If & Testing)

Intune Council (Device Management Only)
├── compliance-deployer (Device Compliance)
├── update-manager (Windows Updates)
└── app-protection (MAM Policies)
```

## What's Moving

### Components Migrating to IAM Council

| Component | Source | Destination |
|-----------|--------|-------------|
| Conditional Access Policies | `intune-configs/ConditionalAccess/` | `iam-configs/ConditionalAccess/` |
| Named Locations | `intune-configs/NamedLocations/` | `iam-configs/NamedLocations/` |
| CA Exclusion Groups | `intune-configs/Groups/` | `iam-configs/Groups/` |
| identity-manager agent | `agents/intune-council/identity-manager.md` | `agents/iam-council/identity-manager.md` |
| conditional-access-deployer agent | `agents/intune-council/conditional-access-deployer.md` | `agents/iam-council/conditional-access-deployer.md` |
| Deployment script logic (CA) | `scripts/intune/Deploy-IntuneConfig.ps1` | `scripts/iam/Deploy-IAMConfig.ps1` |

### Components Staying in Intune Council

| Component | Location |
|-----------|----------|
| Device Compliance Policies | `intune-configs/WINDOWS/CompliancePolicies/` |
| Windows Update Rings | `intune-configs/WINDOWS/WindowsUpdateRings/` |
| Driver Update Profiles | `intune-configs/WINDOWS/DriverUpdateRings/` |
| App Protection Policies | `intune-configs/BYOD/` |
| compliance-deployer agent | `agents/intune-council/compliance-deployer.md` |
| update-manager agent | `agents/intune-council/update-manager.md` |
| app-protection agent | `agents/intune-council/app-protection.md` |

## Migration Steps

### Step 1: Create IAM Configs Directory

```bash
cd /path/to/ALZ-v3

# Create new IAM configs directory structure
mkdir -p iam-configs/{Groups,NamedLocations,ConditionalAccess,ServicePrincipals,SSO,AuthenticationMethods}
```

### Step 2: Move Configuration Files

```bash
# Move Conditional Access policies
mv intune-configs/ConditionalAccess/* iam-configs/ConditionalAccess/

# Move Named Locations
mv intune-configs/NamedLocations/* iam-configs/NamedLocations/

# Move CA-specific groups (exclusion groups)
# Note: Only move groups starting with "CA-Exclusion" or "CA-Pilot"
mv intune-configs/Groups/CA-*.json iam-configs/Groups/
```

### Step 3: Update Configuration References

Review your configuration files and update any cross-references:

**Before** (`intune-configs/ConditionalAccess/CA001-Block-Legacy-Auth.json`):
```json
{
  "conditions": {
    "users": {
      "excludeGroups": ["{{GroupId:CA-Exclusion-EmergencyAccess}}"]
    }
  }
}
```

**After** (no changes needed - placeholders still work):
```json
{
  "conditions": {
    "users": {
      "excludeGroups": ["{{GroupId:CA-Exclusion-EmergencyAccess}}"]
    }
  }
}
```

### Step 4: Update Deployment Workflows

**Old Workflow** (Intune Council):
```bash
# Old: Deploy everything via Intune Council
./scripts/intune/Deploy-IntuneConfig.ps1 -ConfigPath "./intune-configs" -All
```

**New Workflow** (Separated Councils):
```bash
# Step 1: Deploy IAM configurations FIRST (dependencies for CA)
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -All -Environment prod

# Step 2: Deploy Intune configurations (device management)
./scripts/intune/Deploy-IntuneConfig.ps1 -ConfigPath "./intune-configs" -Compliance -UpdateRings -AppProtection
```

### Step 5: Update GitHub Actions Workflows

**New GitHub Actions Workflow** for IAM:

```yaml
# .github/workflows/deploy-iam.yml
name: Deploy IAM Configuration

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        type: choice
        options: [dev, staging, prod]
      deployment_type:
        type: choice
        options: [all, groups, named-locations, conditional-access]

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - uses: actions/checkout@v4
      - name: Deploy IAM
        run: ./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -Environment ${{ inputs.environment }}
```

**Updated Intune Workflow**:

```yaml
# .github/workflows/deploy-intune.yml (updated)
# Remove conditional-access, groups, named-locations options
# Keep only: compliance, update-rings, driver-updates, app-protection
```

### Step 6: Update Documentation

Update your project README and documentation:

```markdown
## Deployment

### IAM Deployment (Identity & Access Management)
```bash
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -ConditionalAccess -Environment prod
```

### Intune Deployment (Device Management)
```bash
./scripts/intune/Deploy-IntuneConfig.ps1 -ConfigPath "./intune-configs" -Compliance -Environment prod
```
```

### Step 7: Migrate Break-Glass Accounts

**CRITICAL**: Ensure break-glass accounts are configured in IAM Council:

```bash
# Create break-glass exclusion groups in IAM configs
cat > iam-configs/Groups/CA-Exclusion-EmergencyAccess.json <<EOF
{
  "displayName": "CA-Exclusion-EmergencyAccess",
  "description": "Emergency access accounts excluded from ALL Conditional Access policies",
  "mailEnabled": false,
  "mailNickname": "ca-exclusion-emergency",
  "securityEnabled": true,
  "groupTypes": []
}
EOF

# Deploy break-glass groups FIRST
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -Groups -Environment prod
```

### Step 8: Test IAM Deployment

```bash
# Step 1: Test in development (What-If mode)
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -All -Environment dev -WhatIf

# Step 2: Deploy in development (actual deployment)
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -All -Environment dev

# Step 3: Validate break-glass accessibility
# Ensure break-glass accounts can still sign in

# Step 4: Deploy to production (report-only mode for CA)
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -ConditionalAccess -Environment prod
# Note: Production CA policies ALWAYS deploy in report-only mode initially
```

### Step 9: Clean Up Old References

```bash
# Remove old CA-related files from Intune Council (optional)
rm -f agents/intune-council/conditional-access-deployer.md.old

# Update intune-council README
# (already done in this migration)
```

## Key Differences

### Security Enhancements in IAM Council

1. **Break-Glass Protection**:
   - Mandatory break-glass exclusions for ALL CA policies
   - Pre-deployment validation enforces this
   - Deployment fails if break-glass exclusions missing

2. **Report-Only Mode Enforcement**:
   - Production CA policies MUST deploy in `enabledForReportingButNotEnforced` state
   - Enforced by deployment script and GitHub Actions
   - Manual override blocked

3. **Multi-Stage Approval Gates**:
   - Development: Auto-approve
   - Staging: Single approver required
   - Production: 2+ approvers required (multi-approval)

4. **Audit Logging**:
   - All IAM changes logged to `scripts/iam/logs/iam-audit.log`
   - Includes operator, timestamp, resource, action
   - Compliance reporting (SOC 2, ISO 27001)

5. **Rollback Capabilities**:
   - Automatic backup before every change
   - One-click rollback to previous state
   - Emergency disable for misconfigured policies

### Deployment Workflow Changes

**Before** (Intune Council):
```bash
# Single command for everything
./scripts/intune/Deploy-IntuneConfig.ps1 -ConfigPath "./intune-configs" -All
```

**After** (Separated Councils):
```bash
# Step 1: IAM (identity and access)
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -All -Environment prod

# Step 2: Intune (device management)
./scripts/intune/Deploy-IntuneConfig.ps1 -ConfigPath "./intune-configs" -Compliance -UpdateRings -AppProtection
```

## Verification Checklist

After migration, verify:

- [ ] All CA policies have break-glass exclusions
- [ ] Break-glass accounts can sign in successfully
- [ ] Production CA policies in report-only mode
- [ ] Audit logs being written to `scripts/iam/logs/iam-audit.log`
- [ ] GitHub Actions approval gates configured
- [ ] Intune device compliance policies still deploy correctly
- [ ] No orphaned configuration files in old locations

## Troubleshooting

### Issue: "Group not found in mapping"

**Cause**: IAM deployment script can't resolve `{{GroupId:...}}` placeholders.

**Solution**:
```bash
# Ensure groups are deployed BEFORE CA policies
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -Groups -Environment prod
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "./iam-configs" -ConditionalAccess -Environment prod
```

### Issue: "Break-glass exclusion missing"

**Cause**: CA policy doesn't have break-glass exclusion group.

**Solution**:
Add exclusion to policy JSON:
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

### Issue: "Production CA policies deploying in enabled state"

**Cause**: Production safety check failed.

**Solution**:
Production deployments are hardcoded to report-only mode. To enable CA policies in production:

1. Deploy in report-only mode
2. Monitor sign-in logs for 1-2 weeks
3. Manually enable via Azure Portal or Graph API after validation

### Issue: "Approval not received"

**Cause**: GitHub Actions environment approvers not configured.

**Solution**:
1. Go to GitHub repo → Settings → Environments
2. Configure `staging` and `prod` environments
3. Add required approvers (staging: 1, prod: 2+)

## Rollback Plan

If migration causes issues:

```bash
# Option 1: Rollback IAM deployment
./scripts/iam/Rollback-IAMDeployment.ps1 -DeploymentId "YYYYMMDD-HHMMSS"

# Option 2: Disable all CA policies temporarily
# Use Azure Portal → Conditional Access → Disable policies

# Option 3: Restore from backup
# Backups stored in: scripts/iam/backups/ca-policies/
```

## Support

For issues or questions:
- Review agent documentation in `agents/iam-council/`
- Check audit logs: `scripts/iam/logs/iam-audit.log`
- Review deployment reports: `scripts/iam/deployment-report-*.md`

## Summary

The IAM Council provides a security-first approach to managing identity and access configurations. While requiring a small adjustment to deployment workflows, the benefits include:

✅ Enhanced security (break-glass protection, report-only enforcement)
✅ Improved compliance (audit logging, approval workflows)
✅ Better separation of concerns (identity vs device management)
✅ Reduced risk (rollback capabilities, What-If testing)
✅ Production-ready (multi-approval gates, monitoring)

Migration is straightforward and can be completed in under 1 hour for most deployments.
