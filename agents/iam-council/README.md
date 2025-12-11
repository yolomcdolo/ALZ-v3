# IAM Council - Identity & Access Management AI Agent System

SECURITY-FIRST architecture for deploying and managing Microsoft Entra ID identity and access management configurations.

## Overview

The IAM Council is a specialized team of AI agents designed to deploy and manage critical identity and access management configurations with the highest security standards. This system is SEPARATE from the Intune Council and focuses exclusively on:

- Conditional Access policies
- Named Locations
- Entra ID security groups (for CA exclusions)
- Service Principal management
- App Registration configurations
- SSO/SAML/OIDC configurations
- Authentication Methods policies
- Identity Protection policies

## Architecture

```
                    ┌─────────────────────────────┐
                    │   iam-council-chair         │
                    │   Security-First Orchestrator│
                    └──────────────┬──────────────┘
                                   │
       ┌───────────────┬───────────┼───────────────┬───────────────┐
       │               │           │               │               │
       ▼               ▼           ▼               ▼               ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│  identity-  │ │conditional- │ │    sso-     │ │  service-   │ │    iam-     │
│   manager   │ │   access    │ │  integrator │ │  principal  │ │  security   │
│             │ │  deployer   │ │             │ │   manager   │ │  auditor    │
│Groups,Named │ │CA Policies  │ │SAML,OIDC    │ │App Regs,    │ │Audit Logs,  │
│Locations    │ │& Sessions   │ │Federation   │ │Credentials  │ │Compliance   │
└─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘
       │               │           │               │               │
       └───────────────┴───────────┴───────────────┴───────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │   iam-deployment-tester     │
                    │   Validation & Security     │
                    └─────────────────────────────┘
```

## Security-First Principles

### 1. Audit Logging
ALL IAM changes are logged with:
- Timestamp
- Operator identity
- Change details (before/after)
- Approval chain
- Deployment environment

### 2. Approval Gates
- **Development**: Auto-approve for testing
- **Staging**: Single approver required
- **Production**: Multi-approver required (2+ approvals)
- Break-glass procedures documented and monitored

### 3. Privileged Identity Management (PIM) Awareness
- Just-in-time access for IAM operations
- Time-limited permissions
- Approval workflows for elevated roles
- Alert on PIM role activations

### 4. Break-Glass Account Protection
- Dedicated exclusion groups for emergency access accounts
- NEVER deploy CA policies without break-glass exclusions
- Monitor break-glass account usage (alert on any sign-in)
- Store break-glass credentials securely (FIDO2 keys recommended)

### 5. Secure Credential Management
- Service Principal credentials stored in Azure Key Vault
- Certificate-based authentication preferred over client secrets
- Automatic credential rotation
- Workload Identity with Managed Identities where possible

### 6. Interactive Authentication
- User-based authentication per session (no stored credentials)
- MFA enforced for all IAM operations
- Session timeout after 1 hour of inactivity

### 7. Report-Only Mode First
- ALL Conditional Access policies deployed in `enabledForReportingButNotEnforced` state initially
- Minimum 1-2 weeks of monitoring in report-only mode
- Sign-in log analysis required before enabling
- What-If tool validation mandatory

### 8. Rollback Capabilities
- Policy backup before any modification
- One-click rollback to previous state
- Rollback plans documented for all changes
- Test rollback procedures quarterly

## Agent Descriptions

| Agent | Purpose | Graph API Scope |
|-------|---------|-----------------|
| iam-council-chair | Orchestrates IAM deployment workflow, security gates | All (read-only) |
| identity-manager | Deploys Entra ID groups and Named Locations | Group.ReadWrite.All, Policy.Read.All |
| conditional-access-deployer | Deploys Conditional Access policies with security validation | Policy.ReadWrite.ConditionalAccess |
| sso-integrator | Configures SSO, SAML, OIDC integrations | Application.ReadWrite.All |
| service-principal-manager | Manages App Registrations and Service Principals | Application.ReadWrite.All, Directory.ReadWrite.All |
| iam-security-auditor | Validates security posture, audit logs, compliance | AuditLog.Read.All, Policy.Read.All |
| iam-deployment-tester | Tests IAM configurations, What-If analysis | Read-only scopes |

## Dependency Chain

IAM deployments MUST follow this order:

```
1. Groups (Entra ID)              ← Base dependency (exclusion groups)
2. Named Locations                ← Geo-based CA policies
3. Conditional Access Policies    ← Depends on Groups & Named Locations
4. Service Principals (optional)  ← For automation scenarios
5. SSO Integrations (optional)    ← Enterprise app configurations
6. Authentication Methods         ← MFA configuration
7. Identity Protection            ← Risk-based policies
```

## Authentication & Authorization

### Interactive User Login (Development/Testing)
```powershell
Connect-MgGraph -Scopes @(
    "Group.ReadWrite.All",
    "Policy.ReadWrite.ConditionalAccess",
    "Application.ReadWrite.All",
    "Directory.ReadWrite.All",
    "AuditLog.Read.All"
)
```

### GitHub Actions (CI/CD)
Uses OIDC federated credentials with:
- Managed Identity authentication
- Azure Key Vault for secrets
- Environment-specific service principals
- Just-in-time permission grants

## Usage

### Full Deployment (Development)
```powershell
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "iam-configs" -Environment dev -All
```

### Selective Deployment with Approval
```powershell
# Deploy only Conditional Access (requires approval in staging/prod)
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "iam-configs" -Environment prod -ConditionalAccess
```

### What-If Analysis
```powershell
./scripts/iam/Deploy-IAMConfig.ps1 -ConfigPath "iam-configs" -Environment prod -All -WhatIf
```

### Rollback to Previous State
```powershell
./scripts/iam/Rollback-IAMDeployment.ps1 -DeploymentId "20251211-143022" -Confirm
```

## Configuration Structure

IAM configurations are stored separately from Intune:

```
iam-configs/
├── Groups/                     # Entra ID security groups
│   ├── CA-Exclusion-EmergencyAccess.json
│   ├── CA-Exclusion-ServiceAccounts.json
│   └── CA-Exclusion-BreakGlass.json
├── NamedLocations/            # Trusted locations
│   ├── Corporate-Network.json
│   └── Trusted-VPN.json
├── ConditionalAccess/         # CA policies (migrated from Intune)
│   ├── CA001-Block-Legacy-Auth.json
│   ├── CA002-Require-MFA-AllUsers.json
│   └── CA003-Block-HighRisk-Countries.json
├── ServicePrincipals/         # App registrations
│   └── sp-automation.json
├── SSO/                       # SSO integrations
│   ├── saml-app1.json
│   └── oidc-app2.json
└── AuthenticationMethods/     # MFA configuration
    └── mfa-policy.json
```

## CI/CD Integration

GitHub Actions workflow: `.github/workflows/deploy-iam.yml`

### Environments
- **dev**: Auto-deploy, no approval required
- **staging**: Single approver, 1-hour deployment window
- **prod**: 2+ approvers, scheduled maintenance window only

### Approval Chain
```
Pull Request → Code Review → Staging Approval → Prod Approval → Deploy
     ↓              ↓              ↓                  ↓             ↓
  Validation   Security Scan   What-If Test    Multi-Approval   Audit Log
```

## Security Features

### 1. Pre-Deployment Validation
- JSON schema validation
- Break-glass exclusion verification
- Policy conflict detection
- What-If impact analysis
- Sign-in log review (report-only policies)

### 2. Deployment Protection
- Multi-stage approval gates
- Automatic backup before changes
- Canary deployment (groups → pilot → all users)
- Real-time monitoring during rollout

### 3. Post-Deployment Monitoring
- Sign-in log analysis (failures, blocks)
- CA policy evaluation metrics
- Break-glass account monitoring
- Anomaly detection (unusual access patterns)

### 4. Compliance & Audit
- Change history tracking
- Compliance reports (SOC 2, ISO 27001)
- Regular security reviews (quarterly)
- Automated compliance checks

## Monitoring & Alerts

### Critical Alerts (Immediate Response)
- Break-glass account sign-in detected
- CA policy modified outside CI/CD
- High volume of user blocks (>5% of sign-ins)
- Service principal credential expiration (<7 days)

### Warning Alerts (Review within 24h)
- Failed sign-ins spike (>10% increase)
- CA policy in report-only mode >30 days
- Unused CA exclusion groups (no members)
- Service principal not used in >90 days

### Info Alerts (Weekly Review)
- New CA policy deployed
- CA policy state changed (report-only → enabled)
- Group membership changes (exclusion groups)
- Named Location IP range modified

## Rollback Procedures

### Automatic Rollback Triggers
- Error rate >1% during deployment
- Critical service unavailable
- Break-glass account blocked (policy misconfiguration)

### Manual Rollback
```powershell
# List available backups
Get-IAMDeploymentHistory -Environment prod -Last 10

# Rollback to specific deployment
Rollback-IAMDeployment -DeploymentId "20251211-143022" -Confirm

# Emergency rollback (disable all CA policies)
Disable-AllConditionalAccessPolicies -EmergencyMode -Confirm
```

## Break-Glass Procedures

### When to Use Break-Glass
- CA policy misconfiguration locked out all admins
- Identity provider outage (federation issues)
- Emergency access required during security incident

### Break-Glass Protocol
1. Retrieve break-glass credentials from secure vault (physical or Azure Key Vault)
2. Sign in using break-glass account (FIDO2 key recommended)
3. Disable problematic CA policy or modify exclusion group
4. Document incident in change log
5. Review and fix root cause within 24 hours
6. Rotate break-glass credentials after use
7. Alert security team immediately

## Disaster Recovery

### Backup Strategy
- Daily automated backups of all IAM configurations
- 90-day retention period
- Off-site backup storage (geo-redundant)
- Quarterly restore testing

### Recovery Time Objectives (RTO)
- Critical CA policies: 15 minutes
- Groups and Named Locations: 30 minutes
- Service Principals: 1 hour
- SSO integrations: 4 hours

### Recovery Point Objectives (RPO)
- CA policies: 1 hour (hourly incremental backups)
- Groups: 24 hours
- All configurations: Point-in-time recovery available

## Migration from Intune Council

### What's Moving
- Conditional Access policies (all 23 policies)
- Named Locations (1 location)
- CA-specific Entra ID groups (3 groups)
- `conditional-access-deployer` agent
- CA-related sections from `identity-manager` agent

### What's Staying in Intune Council
- Device compliance policies
- Windows Update rings
- App Protection policies (MAM)
- Device configuration profiles
- Intune-specific groups

See [Migration Guide](../../docs/iam-migration-guide.md) for step-by-step migration instructions.

## References

- [Microsoft Entra Conditional Access Best Practices](https://learn.microsoft.com/en-us/entra/identity/conditional-access/plan-conditional-access)
- [PIM API Documentation](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-apis)
- [Break-Glass Account Management](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access)
- [Secure Best Practices for Entra ID](https://learn.microsoft.com/en-us/entra/architecture/secure-best-practices)
