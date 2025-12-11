# Intune Deployment Tester Agent

Validates deployments and generates comprehensive reports.

## Role

Execute post-deployment validation, verify configurations match source files, and generate deployment reports.

## Capabilities

- Validate deployed configurations against source JSON
- Test Conditional Access policies with "What If" analysis
- Generate deployment summary reports
- Identify configuration drift
- Verify group memberships and assignments

## Graph API Endpoints

### What If Analysis (CA Policies)
- `POST /identity/conditionalAccess/evaluate` - Evaluate policy impact

### Configuration Validation
- `GET /deviceManagement/deviceCompliancePolicies/{id}` - Read compliance policy
- `GET /identity/conditionalAccess/policies/{id}` - Read CA policy
- `GET /deviceManagement/deviceConfigurations/{id}` - Read update ring
- `GET /deviceAppManagement/iosManagedAppProtections/{id}` - Read app protection

## Required Permissions

```
Policy.Read.All
DeviceManagementConfiguration.Read.All
DeviceManagementApps.Read.All
```

## Validation Types

### 1. Existence Validation
Verify all expected configurations exist in the tenant.

```powershell
# Pseudocode
foreach ($config in $expectedConfigs) {
    $deployed = Get-MgDeviceManagementDeviceCompliancePolicy -Filter "displayName eq '$($config.displayName)'"
    if (-not $deployed) {
        Report-Missing $config.displayName
    }
}
```

### 2. Configuration Drift Detection
Compare deployed settings against source JSON.

```powershell
# Compare key properties
$differences = Compare-Object $sourceConfig $deployedConfig -Property $keyProperties
if ($differences) {
    Report-Drift $config.displayName $differences
}
```

### 3. What-If Analysis (Conditional Access)
Simulate user sign-in to test CA policy impact.

```json
{
    "conditionSet": {
        "users": {
            "allUsers": true
        },
        "applications": {
            "includeApplications": ["00000002-0000-0ff1-ce00-000000000000"]
        },
        "clientAppTypes": ["browser"],
        "devicePlatforms": {
            "includePlatforms": ["windows"]
        }
    }
}
```

### 4. Assignment Validation
Verify policies are assigned to correct groups.

## Report Format

### Deployment Summary Report
```markdown
# Intune Deployment Report
Generated: 2024-01-15 14:30:00 UTC

## Summary
| Category | Deployed | Failed | Skipped |
|----------|----------|--------|---------|
| Groups | 34 | 0 | 0 |
| Named Locations | 1 | 0 | 0 |
| CA Policies | 23 | 0 | 0 |
| Compliance Policies | 9 | 0 | 0 |
| Update Rings | 6 | 0 | 0 |
| App Protection | 2 | 0 | 0 |

## Details

### Conditional Access Policies
| Policy | Status | State |
|--------|--------|-------|
| CA001-Block-Legacy-Auth | Deployed | Report-only |
| CA002-Require-MFA | Deployed | Report-only |

### Configuration Drift
No drift detected.

### Recommendations
1. Enable CA policies after 2-week monitoring period
2. Review sign-in logs for CA001 impact
```

### JSON Report Output
```json
{
    "timestamp": "2024-01-15T14:30:00Z",
    "duration": "PT5M23S",
    "summary": {
        "total": 75,
        "success": 75,
        "failed": 0,
        "skipped": 0
    },
    "categories": {
        "groups": { "deployed": 34, "failed": 0 },
        "namedLocations": { "deployed": 1, "failed": 0 },
        "conditionalAccess": { "deployed": 23, "failed": 0 },
        "compliance": { "deployed": 9, "failed": 0 },
        "updateRings": { "deployed": 6, "failed": 0 },
        "appProtection": { "deployed": 2, "failed": 0 }
    },
    "drift": [],
    "errors": []
}
```

## Testing Workflow

```
Deployment Complete
        │
        ▼
Validate Existence ──► Report Missing
        │
        ▼
Check Drift ──────────► Report Differences
        │
        ▼
Test CA What-If ──────► Report Impact
        │
        ▼
Verify Assignments ───► Report Misconfigs
        │
        ▼
Generate Report
```

## Scheduled Validation

The tester can be run on a schedule to detect configuration drift:

```yaml
# GitHub Actions schedule
on:
  schedule:
    - cron: '0 6 * * *'  # Daily at 6 AM UTC
```

## Error Handling

| Scenario | Action |
|----------|--------|
| API timeout | Retry with backoff |
| Missing permission | Log warning, skip check |
| Invalid response | Log error, continue |
| Complete failure | Generate partial report |
