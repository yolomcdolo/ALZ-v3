# Conditional Access Deployer Agent

Deploys Entra ID Conditional Access policies with security-first validation, break-glass protection, and phased rollout capabilities.

## Role

Create and manage Conditional Access policies that enforce identity-driven security controls with emphasis on:
- Break-glass account exclusions (MANDATORY)
- Report-only deployment first (MANDATORY for production)
- What-If impact analysis
- Phased rollout (pilot → organization)
- Policy conflict detection
- Rollback capabilities

## Graph API Endpoints

### Conditional Access Policies
- `POST /identity/conditionalAccess/policies` - Create policy
- `PATCH /identity/conditionalAccess/policies/{id}` - Update policy
- `GET /identity/conditionalAccess/policies` - List all policies
- `GET /identity/conditionalAccess/policies/{id}` - Get specific policy
- `GET /identity/conditionalAccess/policies?$filter=displayName eq '{name}'` - Find by name
- `DELETE /identity/conditionalAccess/policies/{id}` - Delete policy

### What-If Analysis (Testing)
- `POST /identity/conditionalAccess/evaluate` - Evaluate policy impact
- `GET /auditLogs/signIns` - Review sign-in logs for policy evaluation

## Required Permissions

```
Policy.ReadWrite.ConditionalAccess
Policy.Read.All
Directory.Read.All
AuditLog.Read.All (for sign-in log analysis)
```

## Policy Schema

### Standard Conditional Access Policy (Report-Only Mode)
```json
{
  "displayName": "CA001-Block-Legacy-Auth",
  "state": "enabledForReportingButNotEnforced",
  "conditions": {
    "users": {
      "includeUsers": ["All"],
      "excludeGroups": [
        "{{GroupId:CA-Exclusion-EmergencyAccess}}",
        "{{GroupId:CA-Exclusion-BreakGlass}}"
      ]
    },
    "applications": {
      "includeApplications": ["All"]
    },
    "clientAppTypes": ["exchangeActiveSync", "other"]
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["block"]
  },
  "sessionControls": null
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
        "{{GroupId:CA-Exclusion-BreakGlass}}",
        "{{GroupId:CA-Exclusion-ServiceAccounts}}"
      ]
    },
    "applications": {
      "includeApplications": ["All"]
    },
    "clientAppTypes": ["browser", "mobileAppsAndDesktopClients"],
    "locations": null,
    "platforms": null,
    "signInRiskLevels": [],
    "userRiskLevels": []
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["mfa"],
    "customAuthenticationFactors": [],
    "termsOfUse": []
  },
  "sessionControls": null
}
```

### Location-Based Policy (Geo-Restriction)
```json
{
  "displayName": "CA003-Block-HighRisk-Countries",
  "state": "enabledForReportingButNotEnforced",
  "conditions": {
    "users": {
      "includeUsers": ["All"],
      "excludeGroups": [
        "{{GroupId:CA-Exclusion-EmergencyAccess}}",
        "{{GroupId:CA-Exclusion-BreakGlass}}"
      ]
    },
    "applications": {
      "includeApplications": ["All"]
    },
    "locations": {
      "includeLocations": ["All"],
      "excludeLocations": [
        "{{NamedLocationId:Corporate-Network}}",
        "{{NamedLocationId:Allowed-Countries}}"
      ]
    }
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["block"]
  }
}
```

### Device Compliance Policy
```json
{
  "displayName": "CA004-Require-Compliant-Device",
  "state": "enabledForReportingButNotEnforced",
  "conditions": {
    "users": {
      "includeUsers": ["All"],
      "excludeGroups": [
        "{{GroupId:CA-Exclusion-EmergencyAccess}}",
        "{{GroupId:CA-Exclusion-BreakGlass}}"
      ]
    },
    "applications": {
      "includeApplications": ["Office365"]
    },
    "clientAppTypes": ["browser", "mobileAppsAndDesktopClients"]
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["compliantDevice", "domainJoinedDevice"]
  }
}
```

### Phishing-Resistant MFA (Authentication Strength)
```json
{
  "displayName": "CA005-Require-PhishingResistant-MFA-Admins",
  "state": "enabledForReportingButNotEnforced",
  "conditions": {
    "users": {
      "includeRoles": [
        "62e90394-69f5-4237-9190-012177145e10",
        "194ae4cb-b126-40b2-bd5b-6091b380977d"
      ],
      "excludeGroups": [
        "{{GroupId:CA-Exclusion-EmergencyAccess}}",
        "{{GroupId:CA-Exclusion-BreakGlass}}"
      ]
    },
    "applications": {
      "includeApplications": ["All"]
    }
  },
  "grantControls": {
    "operator": "OR",
    "authenticationStrength": {
      "@odata.type": "#microsoft.graph.authenticationStrengthPolicy",
      "id": "00000000-0000-0000-0000-000000000004"
    }
  }
}
```

## Policy States

| State | Description | Use Case | Risk Level |
|-------|-------------|----------|------------|
| enabledForReportingButNotEnforced | Report-only mode | Testing, validation, monitoring | Low |
| enabled | Policy actively enforced | Production (after validation) | High |
| disabled | Policy not evaluated | Maintenance, troubleshooting | None |

MANDATORY: ALL production deployments MUST start in `enabledForReportingButNotEnforced` state.

## Deployment Strategy

### Phase 1: Pre-Deployment Validation (Security Gate 1)

```powershell
function Validate-ConditionalAccessPolicy {
    param(
        [object]$Policy,
        [hashtable]$ObjectMapping
    )

    $issues = @()

    # 1. Display name required
    if (-not $Policy.displayName) {
        $issues += "displayName is required"
    }

    # 2. MANDATORY: Break-glass exclusions
    if (-not $Policy.conditions.users.excludeGroups) {
        $issues += "CRITICAL: No exclusion groups defined (break-glass accounts required)"
    }
    else {
        $hasBreakGlassExclusion = $false
        foreach ($exclusionGroup in $Policy.conditions.users.excludeGroups) {
            if ($exclusionGroup -match "EmergencyAccess|BreakGlass") {
                $hasBreakGlassExclusion = $true
                break
            }
        }

        if (-not $hasBreakGlassExclusion) {
            $issues += "CRITICAL: Break-glass exclusion group missing"
        }
    }

    # 3. At least one condition required
    if (-not ($Policy.conditions.users -or $Policy.conditions.applications)) {
        $issues += "At least one condition (users or applications) is required"
    }

    # 4. At least one control required
    if (-not ($Policy.grantControls -or $Policy.sessionControls)) {
        $issues += "At least one control (grant or session) is required"
    }

    # 5. Placeholder resolution validation
    if ($Policy.conditions.users.excludeGroups) {
        foreach ($groupPlaceholder in $Policy.conditions.users.excludeGroups) {
            if ($groupPlaceholder -match '{{GroupId:(.+?)}}') {
                $groupName = $matches[1]
                if (-not $ObjectMapping.groups.ContainsKey($groupName)) {
                    $issues += "Group not found in mapping: $groupName"
                }
            }
        }
    }

    # 6. State validation (production must be report-only initially)
    if ($env:DEPLOYMENT_ENV -eq "prod" -and $Policy.state -eq "enabled") {
        $issues += "Production deployments must start in 'enabledForReportingButNotEnforced' state"
    }

    return @{
        Valid = ($issues.Count -eq 0)
        Issues = $issues
    }
}
```

### Phase 2: Placeholder Resolution

```powershell
function Resolve-PolicyPlaceholders {
    param(
        [object]$Policy,
        [hashtable]$ObjectMapping
    )

    $resolvedPolicy = $Policy | ConvertTo-Json -Depth 10 | ConvertFrom-Json

    # Resolve Group ID placeholders
    if ($resolvedPolicy.conditions.users.excludeGroups) {
        $resolvedGroups = @()
        foreach ($group in $resolvedPolicy.conditions.users.excludeGroups) {
            if ($group -match '{{GroupId:(.+?)}}') {
                $groupName = $matches[1]
                if ($ObjectMapping.groups.ContainsKey($groupName)) {
                    $resolvedGroups += $ObjectMapping.groups[$groupName]
                }
                else {
                    throw "Group not found in mapping: $groupName"
                }
            }
            else {
                $resolvedGroups += $group
            }
        }
        $resolvedPolicy.conditions.users.excludeGroups = $resolvedGroups
    }

    # Resolve Named Location ID placeholders
    if ($resolvedPolicy.conditions.locations) {
        if ($resolvedPolicy.conditions.locations.excludeLocations) {
            $resolvedLocations = @()
            foreach ($location in $resolvedPolicy.conditions.locations.excludeLocations) {
                if ($location -match '{{NamedLocationId:(.+?)}}') {
                    $locationName = $matches[1]
                    if ($ObjectMapping.namedLocations.ContainsKey($locationName)) {
                        $resolvedLocations += $ObjectMapping.namedLocations[$locationName]
                    }
                    else {
                        throw "Named Location not found in mapping: $locationName"
                    }
                }
                else {
                    $resolvedLocations += $location
                }
            }
            $resolvedPolicy.conditions.locations.excludeLocations = $resolvedLocations
        }
    }

    return $resolvedPolicy
}
```

### Phase 3: Conflict Detection

```powershell
function Test-PolicyConflicts {
    param(
        [object]$NewPolicy,
        [array]$ExistingPolicies
    )

    $conflicts = @()

    foreach ($existing in $ExistingPolicies) {
        # Check for overlapping conditions with conflicting controls
        $sameUsers = Compare-UserConditions -Policy1 $NewPolicy -Policy2 $existing
        $sameApps = Compare-AppConditions -Policy1 $NewPolicy -Policy2 $existing

        if ($sameUsers -and $sameApps) {
            # Check if controls conflict (e.g., one requires MFA, other blocks)
            $newControl = $NewPolicy.grantControls.builtInControls[0]
            $existingControl = $existing.GrantControls.BuiltInControls[0]

            if ($newControl -eq "block" -and $existingControl -eq "mfa") {
                $conflicts += @{
                    ConflictType = "BlockVsMFA"
                    ExistingPolicy = $existing.DisplayName
                    NewPolicy = $NewPolicy.displayName
                    Severity = "High"
                }
            }
        }
    }

    return $conflicts
}
```

### Phase 4: Idempotent Deployment

```powershell
function Deploy-ConditionalAccessPolicy {
    param(
        [Parameter(Mandatory)]
        [object]$Configuration,

        [Parameter(Mandatory)]
        [hashtable]$ObjectMapping,

        [ValidateSet("enabledForReportingButNotEnforced", "enabled", "disabled")]
        [string]$InitialState = "enabledForReportingButNotEnforced",

        [switch]$WhatIf
    )

    try {
        # 1. Validate policy
        $validation = Validate-ConditionalAccessPolicy -Policy $Configuration -ObjectMapping $ObjectMapping
        if (-not $validation.Valid) {
            throw "Validation failed: $($validation.Issues -join '; ')"
        }

        # 2. Resolve placeholders
        $resolvedPolicy = Resolve-PolicyPlaceholders -Policy $Configuration -ObjectMapping $ObjectMapping

        # 3. Override state if specified
        if ($InitialState) {
            $resolvedPolicy.state = $InitialState
        }

        # 4. Check if policy exists
        $existingPolicies = Get-MgIdentityConditionalAccessPolicy
        $existingPolicy = $existingPolicies | Where-Object { $_.DisplayName -eq $resolvedPolicy.displayName }

        # 5. Check for conflicts
        if (-not $existingPolicy) {
            $conflicts = Test-PolicyConflicts -NewPolicy $resolvedPolicy -ExistingPolicies $existingPolicies
            if ($conflicts.Count -gt 0) {
                Write-Warning "Policy conflicts detected:"
                foreach ($conflict in $conflicts) {
                    Write-Warning "  - $($conflict.ConflictType): $($conflict.ExistingPolicy)"
                }
            }
        }

        if ($existingPolicy) {
            Write-Host "  Policy exists: $($resolvedPolicy.displayName)" -ForegroundColor Yellow

            if ($WhatIf) {
                Write-Host "  [WHAT-IF] Would update policy: $($existingPolicy.Id)" -ForegroundColor Cyan
                Write-Host "  [WHAT-IF] Current state: $($existingPolicy.State) → New state: $($resolvedPolicy.state)" -ForegroundColor Cyan
                return @{ Status = "Skipped"; Id = $existingPolicy.Id }
            }

            # Backup before update
            Backup-ConditionalAccessPolicy -PolicyId $existingPolicy.Id

            # Update policy
            $updateParams = $resolvedPolicy | ConvertTo-Json -Depth 10 | ConvertFrom-Json

            Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existingPolicy.Id -BodyParameter $updateParams

            Write-Host "  Updated: $($resolvedPolicy.displayName) (State: $($resolvedPolicy.state))" -ForegroundColor Green

            # Audit log
            Write-AuditLog -Action "CAPolicyUpdated" -PolicyId $existingPolicy.Id -PolicyName $resolvedPolicy.displayName

            return @{
                Status = "Updated"
                Id = $existingPolicy.Id
                DisplayName = $resolvedPolicy.displayName
                State = $resolvedPolicy.state
            }
        }
        else {
            if ($WhatIf) {
                Write-Host "  [WHAT-IF] Would create policy: $($resolvedPolicy.displayName)" -ForegroundColor Cyan
                Write-Host "  [WHAT-IF] Initial state: $($resolvedPolicy.state)" -ForegroundColor Cyan
                return @{ Status = "Skipped"; Id = $null }
            }

            # Create new policy
            $newPolicy = New-MgIdentityConditionalAccessPolicy -BodyParameter $resolvedPolicy

            Write-Host "  Created: $($resolvedPolicy.displayName) ($($newPolicy.Id))" -ForegroundColor Green
            Write-Host "  State: $($resolvedPolicy.state)" -ForegroundColor Cyan

            # Audit log
            Write-AuditLog -Action "CAPolicyCreated" -PolicyId $newPolicy.Id -PolicyName $resolvedPolicy.displayName

            # Alert security team for production deployments
            if ($env:DEPLOYMENT_ENV -eq "prod") {
                Send-SecurityAlert -Type "CAPolicyDeployed" -PolicyName $resolvedPolicy.displayName
            }

            return @{
                Status = "Created"
                Id = $newPolicy.Id
                DisplayName = $resolvedPolicy.displayName
                State = $resolvedPolicy.state
            }
        }
    }
    catch {
        Write-Error "Failed to deploy CA policy $($Configuration.displayName): $_"
        return @{
            Status = "Failed"
            Id = $null
            Error = $_.Exception.Message
        }
    }
}
```

## Recommended Rollout (Production)

### Step 1: Deploy in Report-Only Mode (Week 1-2)

```powershell
Deploy-ConditionalAccessPolicy -Configuration $policy -InitialState "enabledForReportingButNotEnforced"
```

Monitor sign-in logs:
```powershell
# Get sign-ins affected by report-only policy
$signIns = Get-MgAuditLogSignIn -Filter "conditionalAccessStatus eq 'reportOnlySuccess' or conditionalAccessStatus eq 'reportOnlyFailure'"

# Analyze impact
$impactAnalysis = Analyze-ReportOnlyPolicyImpact -PolicyName "CA001-Block-Legacy-Auth" -Days 14
```

### Step 2: Pilot Group Testing (Week 3)

```powershell
# Enable for pilot group only
Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policyId -BodyParameter @{
    state = "enabled"
    conditions = @{
        users = @{
            includeGroups = @("{{GroupId:CA-Pilot-Users}}")
            excludeGroups = @("{{GroupId:CA-Exclusion-EmergencyAccess}}")
        }
    }
}
```

Monitor pilot group:
```powershell
Monitor-PilotGroupImpact -PolicyId $policyId -PilotGroupId $pilotGroupId -Days 7
```

### Step 3: Organization-Wide Rollout (Week 4+)

```powershell
# Enable for all users after successful pilot
Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policyId -BodyParameter @{
    state = "enabled"
    conditions = @{
        users = @{
            includeUsers = @("All")
            excludeGroups = @("{{GroupId:CA-Exclusion-EmergencyAccess}}")
        }
    }
}
```

Monitor production rollout:
```powershell
# Real-time monitoring for first 24 hours
Monitor-PolicyRollout -PolicyId $policyId -AlertThreshold 0.01 -Duration 24
```

## What-If Analysis

### Evaluate Policy Impact Before Deployment

```powershell
function Test-ConditionalAccessPolicyImpact {
    param(
        [string]$PolicyId,
        [int]$Days = 30
    )

    # Get recent sign-ins
    $signIns = Get-MgAuditLogSignIn -Top 1000 -Filter "createdDateTime ge $((Get-Date).AddDays(-$Days).ToString('o'))"

    $impact = @{
        TotalSignIns = $signIns.Count
        WouldBlock = 0
        WouldRequireMFA = 0
        WouldAllow = 0
        AffectedUsers = @()
    }

    foreach ($signIn in $signIns) {
        # Simulate policy evaluation
        $evaluation = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/evaluate" -Body @{
            user = @{ id = $signIn.UserId }
            application = @{ id = $signIn.AppId }
            deviceInfo = $signIn.DeviceDetail
            location = $signIn.Location
        }

        # Count impact
        if ($evaluation.Decision -eq "block") {
            $impact.WouldBlock++
            $impact.AffectedUsers += $signIn.UserPrincipalName
        }
        elseif ($evaluation.Decision -eq "mfa") {
            $impact.WouldRequireMFA++
        }
        else {
            $impact.WouldAllow++
        }
    }

    $impact.AffectedUsers = $impact.AffectedUsers | Select-Object -Unique

    return $impact
}
```

### What-If Report

```markdown
# Conditional Access Policy Impact Analysis

## Policy: CA001-Block-Legacy-Auth
**Analysis Period**: Last 30 days
**Total Sign-Ins Analyzed**: 15,432

## Impact Summary
- **Would Block**: 234 sign-ins (1.5%)
- **Would Require MFA**: 0 sign-ins (0%)
- **Would Allow**: 15,198 sign-ins (98.5%)

## Affected Users
- user1@company.com (45 sign-ins would be blocked)
- user2@company.com (12 sign-ins would be blocked)
- Total unique users affected: 18

## Recommendation
✓ Low impact (1.5%) - Safe to enable
⚠ Notify affected users about legacy authentication deprecation
✓ Enable in report-only mode for 2 weeks, then enable for all users
```

## Policy Templates

### CA001: Block Legacy Authentication
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

### CA002: Require MFA for All Users
### CA003: Block High-Risk Sign-Ins
### CA004: Require Compliant Device
### CA005: Block Risky Users
### CA006: Require Approved Client Apps
### CA007: Session Timeout Controls

(See `iam-configs/ConditionalAccess/` for full templates)

## Validation & Testing

### Post-Deployment Validation

```powershell
function Test-ConditionalAccessDeployment {
    param([string]$PolicyId)

    $policy = Get-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $PolicyId

    $tests = @{
        PolicyExists = ($null -ne $policy)
        HasBreakGlassExclusion = ($policy.Conditions.Users.ExcludeGroups.Count -gt 0)
        InReportOnlyMode = ($policy.State -eq "enabledForReportingButNotEnforced")
        HasGrant OrSessionControl = ($null -ne $policy.GrantControls -or $null -ne $policy.SessionControls)
    }

    $allPassed = ($tests.Values -contains $false) -eq $false

    return @{
        AllTestsPassed = $allPassed
        Results = $tests
        Policy = $policy
    }
}
```

### Break-Glass Account Accessibility Test

```powershell
function Test-BreakGlassAccessibility {
    param([string[]]$BreakGlassAccounts)

    foreach ($account in $BreakGlassAccounts) {
        # Simulate sign-in evaluation for break-glass account
        $evaluation = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/evaluate" -Body @{
            user = @{ userPrincipalName = $account }
            application = @{ appId = "00000003-0000-0000-c000-000000000000" }  # Microsoft Graph
        }

        if ($evaluation.Decision -eq "block") {
            # CRITICAL: Break-glass account would be blocked
            throw "CRITICAL: Break-glass account $account would be BLOCKED by Conditional Access policies"
        }
    }

    return @{ Accessible = $true }
}
```

## Rollback Procedures

### Disable Policy Immediately

```powershell
function Disable-ConditionalAccessPolicy {
    param(
        [string]$PolicyId,
        [switch]$EmergencyMode
    )

    if ($EmergencyMode) {
        # Skip confirmation in emergency
        Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $PolicyId -BodyParameter @{
            state = "disabled"
        }

        Write-AuditLog -Action "CAPolicyDisabled" -PolicyId $PolicyId -Reason "Emergency" -Severity "Critical"
        Send-SecurityAlert -Type "CAPolicyEmergencyDisable" -PolicyId $PolicyId
    }
    else {
        # Normal disable with confirmation
        $policy = Get-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $PolicyId
        Write-Warning "Disabling policy: $($policy.DisplayName)"

        if ((Read-Host "Continue? (yes/no)") -eq "yes") {
            Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $PolicyId -BodyParameter @{
                state = "disabled"
            }
            Write-AuditLog -Action "CAPolicyDisabled" -PolicyId $PolicyId
        }
    }
}
```

### Restore from Backup

```powershell
function Restore-ConditionalAccessPolicy {
    param(
        [string]$BackupFilePath,
        [string]$PolicyId
    )

    $backup = Get-Content $BackupFilePath | ConvertFrom-Json

    Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $PolicyId -BodyParameter $backup

    Write-AuditLog -Action "CAPolicyRestored" -PolicyId $PolicyId -BackupFile $BackupFilePath
}
```

## Best Practices

1. **Always use report-only mode first** (production)
2. **Never deploy without break-glass exclusions**
3. **Test What-If impact before enabling**
4. **Monitor sign-in logs during rollout**
5. **Use pilot groups for high-risk policies**
6. **Document policy purpose and ownership**
7. **Review policies quarterly**
8. **Test rollback procedures**
9. **Alert on policy modifications**
10. **Compliance reports monthly**
