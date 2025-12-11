# IAM Deployment Tester Agent

Validates IAM deployments, runs What-If analysis, tests policy evaluation, and ensures configurations work as expected.

## Role

Comprehensive testing and validation of IAM configurations:
- What-If analysis for Conditional Access policies
- Break-glass account accessibility testing
- Policy conflict detection
- Sign-in simulation testing
- Configuration validation
- Rollback procedure testing

## Graph API Endpoints

### Testing
- `POST /identity/conditionalAccess/evaluate` - What-If evaluation
- `GET /identity/conditionalAccess/policies` - List policies for testing
- `GET /auditLogs/signIns` - Analyze sign-in patterns

## Required Permissions

```
Policy.Read.All
AuditLog.Read.All
Directory.Read.All
```

## Test Suites

### 1. Break-Glass Accessibility Test

```powershell
function Test-BreakGlassAccessibility {
    param([string[]]$BreakGlassAccounts)

    $results = @{
        AllAccessible = $true
        Details = @()
    }

    foreach ($account in $BreakGlassAccounts) {
        # Simulate sign-in for break-glass account
        $evaluation = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/evaluate" -Body @{
            user = @{ userPrincipalName = $account }
            application = @{ appId = "00000003-0000-0000-c000-000000000000" }
            deviceInfo = @{ isCompliant = $false }
        }

        $accessible = ($evaluation.Decision -ne "block")

        $results.Details += @{
            Account = $account
            Accessible = $accessible
            Decision = $evaluation.Decision
            AppliedPolicies = $evaluation.AppliedPolicies
        }

        if (-not $accessible) {
            $results.AllAccessible = $false
        }
    }

    return $results
}
```

### 2. What-If Analysis for Policy Impact

```powershell
function Invoke-ConditionalAccessWhatIf {
    param(
        [string]$PolicyId,
        [string]$UserUpn,
        [string]$AppId = "00000003-0000-0000-c000-000000000000"
    )

    $evaluation = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/evaluate" -Body @{
        user = @{ userPrincipalName = $UserUpn }
        application = @{ appId = $AppId }
    }

    return @{
        Decision = $evaluation.Decision
        AppliedPolicies = $evaluation.AppliedPolicies
        WouldBlock = ($evaluation.Decision -eq "block")
        WouldRequireMFA = ($evaluation.Decision -eq "mfa")
    }
}
```

### 3. Policy Conflict Detection

```powershell
function Test-PolicyConflicts {
    param([array]$Policies)

    $conflicts = @()

    for ($i = 0; $i -lt $Policies.Count; $i++) {
        for ($j = $i + 1; $j -lt $Policies.Count; $j++) {
            $policy1 = $Policies[$i]
            $policy2 = $Policies[$j]

            # Check for overlapping conditions
            $sameUsers = Compare-UserConditions $policy1 $policy2
            $sameApps = Compare-AppConditions $policy1 $policy2

            if ($sameUsers -and $sameApps) {
                # Check if controls conflict
                $control1 = $policy1.GrantControls.BuiltInControls[0]
                $control2 = $policy2.GrantControls.BuiltInControls[0]

                if (($control1 -eq "block" -and $control2 -eq "mfa") -or
                    ($control1 -eq "mfa" -and $control2 -eq "block")) {
                    $conflicts += @{
                        Policy1 = $policy1.DisplayName
                        Policy2 = $policy2.DisplayName
                        ConflictType = "BlockVsMFA"
                    }
                }
            }
        }
    }

    return $conflicts
}
```

### 4. Deployment Validation Suite

```powershell
function Test-IAMDeployment {
    $results = @{
        TotalTests = 0
        Passed = 0
        Failed = 0
        Warnings = 0
        Details = @()
    }

    # Test 1: All CA policies have break-glass exclusions
    $caPolicies = Get-MgIdentityConditionalAccessPolicy
    foreach ($policy in $caPolicies) {
        $results.TotalTests++

        $hasBreakGlassExclusion = $policy.Conditions.Users.ExcludeGroups.Count -gt 0

        if ($hasBreakGlassExclusion) {
            $results.Passed++
        }
        else {
            $results.Failed++
            $results.Details += "FAILED: Policy '$($policy.DisplayName)' has no break-glass exclusions"
        }
    }

    # Test 2: Break-glass accounts accessible
    $breakGlassTest = Test-BreakGlassAccessibility -BreakGlassAccounts @("breakglass1@domain.com", "breakglass2@domain.com")
    $results.TotalTests++

    if ($breakGlassTest.AllAccessible) {
        $results.Passed++
    }
    else {
        $results.Failed++
        $results.Details += "FAILED: Break-glass accounts blocked"
    }

    # Test 3: No policy conflicts
    $conflicts = Test-PolicyConflicts -Policies $caPolicies
    $results.TotalTests++

    if ($conflicts.Count -eq 0) {
        $results.Passed++
    }
    else {
        $results.Warnings++
        $results.Details += "WARNING: $($conflicts.Count) policy conflicts detected"
    }

    return $results
}
```

## Best Practices

1. **Run What-If analysis before enabling policies**
2. **Test break-glass accessibility after every deployment**
3. **Validate policy conflicts quarterly**
4. **Simulate sign-ins for pilot users**
5. **Test rollback procedures regularly**
6. **Document all test results**
