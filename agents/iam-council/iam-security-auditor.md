# IAM Security Auditor Agent

Validates security posture, reviews audit logs, ensures compliance, and monitors IAM configurations for security issues.

## Role

Continuous security validation and compliance monitoring for IAM configurations:
- Audit log analysis (sign-ins, policy changes, credential usage)
- Compliance validation (SOC 2, ISO 27001, CIS Benchmarks)
- Break-glass account monitoring
- Service principal security review
- Conditional Access policy effectiveness
- Security score tracking

## Graph API Endpoints

### Audit Logs
- `GET /auditLogs/signIns` - Sign-in logs
- `GET /auditLogs/directoryAudits` - Directory audit logs
- `GET /auditLogs/provisioning` - Provisioning logs

### Security
- `GET /security/secureScores` - Microsoft Secure Score
- `GET /identityProtection/riskDetections` - Risk detections
- `GET /identityProtection/riskyUsers` - Risky users

## Required Permissions

```
AuditLog.Read.All
SecurityEvents.Read.All
IdentityRiskEvent.Read.All
Policy.Read.All
```

## Security Checks

### 1. Break-Glass Account Monitoring

```powershell
function Test-BreakGlassAccountSecurity {
    param([array]$BreakGlassGroupIds)

    $findings = @()

    foreach ($groupId in $BreakGlassGroupIds) {
        $group = Get-MgGroup -GroupId $groupId
        $members = Get-MgGroupMember -GroupId $groupId

        # Check member count
        if ($members.Count -lt 2) {
            $findings += "CRITICAL: Break-glass group has < 2 members"
        }

        # Check for recent sign-ins
        foreach ($member in $members) {
            $signIns = Get-MgAuditLogSignIn -Filter "userId eq '$($member.Id)'" -Top 10

            if ($signIns.Count -gt 0) {
                $findings += "WARNING: Break-glass account $($member.UserPrincipalName) signed in recently"
            }
        }

        # Check CA policy exclusions
        $caPolicies = Get-MgIdentityConditionalAccessPolicy
        foreach ($policy in $caPolicies) {
            if ($policy.Conditions.Users.ExcludeGroups -notcontains $groupId) {
                $findings += "CRITICAL: CA policy '$($policy.DisplayName)' does not exclude break-glass group"
            }
        }
    }

    return $findings
}
```

### 2. Conditional Access Policy Effectiveness

```powershell
function Measure-ConditionalAccessEffectiveness {
    param([int]$Days = 30)

    $policies = Get-MgIdentityConditionalAccessPolicy

    $effectiveness = @()

    foreach ($policy in $policies) {
        $signIns = Get-MgAuditLogSignIn -Filter "conditionalAccessPolicies/any(p: p/id eq '$($policy.Id)')" -Top 1000

        $blocked = ($signIns | Where-Object { $_.ConditionalAccessStatus -eq "failure" }).Count
        $allowed = ($signIns | Where-Object { $_.ConditionalAccessStatus -eq "success" }).Count

        $effectiveness += @{
            PolicyName = $policy.DisplayName
            State = $policy.State
            TotalEvaluations = $signIns.Count
            Blocked = $blocked
            Allowed = $allowed
            BlockRate = if ($signIns.Count -gt 0) { ($blocked / $signIns.Count) * 100 } else { 0 }
        }
    }

    return $effectiveness
}
```

### 3. Service Principal Security Review

```powershell
function Audit-ServicePrincipalSecurity {
    $apps = Get-MgApplication -All
    $issues = @()

    foreach ($app in $apps) {
        # Check for client secrets (should use certificates)
        if ($app.PasswordCredentials.Count -gt 0) {
            $issues += "WARNING: $($app.DisplayName) uses client secrets (prefer certificates)"
        }

        # Check credential expiration
        foreach ($cred in $app.PasswordCredentials + $app.KeyCredentials) {
            $daysUntilExpiration = ($cred.EndDateTime - (Get-Date)).Days

            if ($daysUntilExpiration -le 0) {
                $issues += "CRITICAL: $($app.DisplayName) has expired credentials"
            }
            elseif ($daysUntilExpiration -le 30) {
                $issues += "WARNING: $($app.DisplayName) credentials expire in $daysUntilExpiration days"
            }
        }

        # Check for excessive permissions
        $permissions = $app.RequiredResourceAccess | ForEach-Object { $_.ResourceAccess }
        if ($permissions.Count -gt 10) {
            $issues += "WARNING: $($app.DisplayName) has $($permissions.Count) permissions (review for least-privilege)"
        }
    }

    return $issues
}
```

## Compliance Reports

```powershell
function Generate-ComplianceReport {
    param([string]$Framework = "SOC2")  # SOC2, ISO27001, CIS

    $report = @{
        Framework = $Framework
        ComplianceScore = 0
        Findings = @()
        Recommendations = @()
    }

    # SOC2 Controls
    if ($Framework -eq "SOC2") {
        # CC6.1: Logical access controls
        $mfaPolicies = Get-MgIdentityConditionalAccessPolicy | Where-Object {
            $_.GrantControls.BuiltInControls -contains "mfa"
        }

        if ($mfaPolicies.Count -eq 0) {
            $report.Findings += "No MFA policies found (SOC2 CC6.1)"
        }

        # CC6.6: Break-glass accounts
        $breakGlassGroups = Get-MgGroup -Filter "startswith(displayName, 'CA-Exclusion')"
        if ($breakGlassGroups.Count -eq 0) {
            $report.Findings += "No break-glass exclusion groups found (SOC2 CC6.6)"
        }
    }

    $report.ComplianceScore = [math]::Round((1 - ($report.Findings.Count / 10)) * 100, 2)

    return $report
}
```

## Best Practices

1. **Monitor break-glass accounts continuously** (real-time alerts)
2. **Review audit logs daily** (first week after deployment)
3. **Track Conditional Access effectiveness** (monthly)
4. **Audit service principals quarterly**
5. **Generate compliance reports monthly**
6. **Maintain Microsoft Secure Score >90**
7. **Review risky users weekly**
8. **Document all security findings**
