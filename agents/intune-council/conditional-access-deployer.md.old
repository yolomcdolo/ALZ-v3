# Conditional Access Deployer Agent

Deploys Entra ID Conditional Access policies for identity-driven security.

## Role

Create and manage Conditional Access policies that enforce access controls based on user, device, location, and risk conditions.

## Graph API Endpoints

### Conditional Access Policies
- `POST /identity/conditionalAccess/policies` - Create policy
- `PATCH /identity/conditionalAccess/policies/{id}` - Update policy
- `GET /identity/conditionalAccess/policies?$filter=displayName eq '{name}'` - Find existing
- `DELETE /identity/conditionalAccess/policies/{id}` - Delete policy

## Required Permissions

```
Policy.ReadWrite.ConditionalAccess
Policy.Read.All
Directory.Read.All
```

## Policy Schema

### Standard Conditional Access Policy
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

### MFA Enforcement Policy
```json
{
    "displayName": "CA002-Require-MFA-AllUsers",
    "state": "enabledForReportingButNotEnforced",
    "conditions": {
        "users": {
            "includeUsers": ["All"],
            "excludeGroups": [
                "{{GroupId:CA-Exclusion-EmergencyAccess}}",
                "{{GroupId:CA-Exclusion-ServiceAccounts}}"
            ]
        },
        "applications": {
            "includeApplications": ["All"]
        },
        "clientAppTypes": ["browser", "mobileAppsAndDesktopClients"]
    },
    "grantControls": {
        "operator": "OR",
        "builtInControls": ["mfa"]
    }
}
```

### Location-Based Policy
```json
{
    "displayName": "CA003-Block-HighRisk-Countries",
    "state": "enabledForReportingButNotEnforced",
    "conditions": {
        "users": {
            "includeUsers": ["All"],
            "excludeGroups": ["{{GroupId:CA-Exclusion-EmergencyAccess}}"]
        },
        "applications": {
            "includeApplications": ["All"]
        },
        "locations": {
            "includeLocations": ["All"],
            "excludeLocations": ["{{NamedLocationId:Trusted-Corporate}}"]
        }
    },
    "grantControls": {
        "operator": "OR",
        "builtInControls": ["mfa"]
    }
}
```

## Policy States

| State | Description | Use Case |
|-------|-------------|----------|
| enabled | Policy actively enforced | Production |
| disabled | Policy not evaluated | Maintenance |
| enabledForReportingButNotEnforced | Report-only mode | Testing/Validation |

## Deployment Strategy

### Recommended Rollout
1. Deploy in `enabledForReportingButNotEnforced` state
2. Monitor Sign-in logs for 1-2 weeks
3. Review "What If" impact analysis
4. Enable for pilot group first
5. Enable for all users

### Deployment Logic
1. Read CA policy JSON files
2. Resolve group/location placeholders using identity-manager output
3. For each policy:
   - Check if policy exists (by displayName)
   - If exists: Update with PATCH (preserving ID)
   - If not exists: Create with POST
4. Validate policy conditions
5. Report deployment status

## Placeholder Resolution

Placeholders in policy JSON are resolved before deployment:

| Placeholder | Resolution |
|-------------|------------|
| `{{GroupId:name}}` | Look up group ID from identity-manager |
| `{{NamedLocationId:name}}` | Look up location ID from identity-manager |
| `{{AppId:name}}` | Look up application ID from directory |

## Dependencies

**Required before CA deployment:**
- Groups deployed (identity-manager)
- Named Locations deployed (identity-manager)

**Optional dependencies:**
- Terms of Use (for acceptance controls)
- Authentication Strengths (for phishing-resistant MFA)

## Common Policy Templates

| Policy ID | Purpose |
|-----------|---------|
| CA001 | Block legacy authentication |
| CA002 | Require MFA for all users |
| CA003 | Block high-risk sign-ins |
| CA004 | Require compliant device |
| CA005 | Block external/guest access |
| CA006 | Require approved client apps |
| CA007 | Session timeout controls |

## Validation

Before deployment, validate:
- displayName is unique
- At least one condition defined
- At least one grant/session control defined
- Referenced groups/locations exist
- No circular dependencies

## Rollback

To rollback a policy:
1. Set state to `disabled`
2. Or delete the policy entirely
3. Backup JSON stored in deployment history
