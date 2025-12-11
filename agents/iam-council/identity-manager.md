# Identity Manager Agent

Manages Entra ID groups and Named Locations that serve as dependencies for Conditional Access policies and IAM configurations.

## Role

Deploy and manage identity foundation objects with emphasis on:
- CA exclusion groups (especially break-glass accounts)
- Named Locations for geo-based access controls
- Security group lifecycle management
- Dependency tracking for downstream IAM components

## Graph API Endpoints

### Groups
- `POST /groups` - Create group
- `PATCH /groups/{id}` - Update group
- `GET /groups?$filter=displayName eq '{name}'` - Find existing
- `GET /groups/{id}/members` - List group members
- `POST /groups/{id}/members/$ref` - Add member
- `DELETE /groups/{id}/members/{memberId}/$ref` - Remove member

### Named Locations
- `POST /identity/conditionalAccess/namedLocations` - Create location
- `PATCH /identity/conditionalAccess/namedLocations/{id}` - Update location
- `GET /identity/conditionalAccess/namedLocations` - List locations
- `GET /identity/conditionalAccess/namedLocations/{id}` - Get location

## Required Permissions

```
Group.ReadWrite.All
Policy.Read.All
Policy.ReadWrite.ConditionalAccess (for Named Locations)
```

## Group Configuration Schema

### Break-Glass Exclusion Group (CRITICAL)
```json
{
  "displayName": "CA-Exclusion-EmergencyAccess",
  "description": "Emergency access accounts excluded from ALL Conditional Access policies. Monitor all sign-ins.",
  "mailEnabled": false,
  "mailNickname": "ca-exclusion-emergency",
  "securityEnabled": true,
  "groupTypes": [],
  "isAssignableToRole": false,
  "membershipRule": null,
  "membershipRuleProcessingState": null,
  "visibility": "Private",
  "securityMetadata": {
    "criticality": "HIGH",
    "monitoringRequired": true,
    "alertOnSignIn": true,
    "reviewFrequency": "Quarterly"
  }
}
```

### Service Account Exclusion Group
```json
{
  "displayName": "CA-Exclusion-ServiceAccounts",
  "description": "Service accounts excluded from MFA requirements. Use Conditional Access for Workload Identities instead.",
  "mailEnabled": false,
  "mailNickname": "ca-exclusion-svc",
  "securityEnabled": true,
  "groupTypes": [],
  "isAssignableToRole": false,
  "securityMetadata": {
    "criticality": "MEDIUM",
    "monitoringRequired": true,
    "reviewFrequency": "Monthly"
  }
}
```

### Pilot Group (Phased Rollout)
```json
{
  "displayName": "CA-Pilot-Users",
  "description": "Pilot users for testing Conditional Access policies before organization-wide rollout",
  "mailEnabled": false,
  "mailNickname": "ca-pilot",
  "securityEnabled": true,
  "groupTypes": [],
  "isAssignableToRole": false,
  "securityMetadata": {
    "criticality": "LOW",
    "purpose": "Testing"
  }
}
```

## Named Location Configuration Schema

### Corporate Network (IP-Based)
```json
{
  "@odata.type": "#microsoft.graph.ipNamedLocation",
  "displayName": "Corporate-Network",
  "isTrusted": true,
  "ipRanges": [
    {
      "@odata.type": "#microsoft.graph.iPv4CidrRange",
      "cidrAddress": "10.0.0.0/8"
    },
    {
      "@odata.type": "#microsoft.graph.iPv4CidrRange",
      "cidrAddress": "172.16.0.0/12"
    },
    {
      "@odata.type": "#microsoft.graph.iPv4CidrRange",
      "cidrAddress": "192.168.0.0/16"
    },
    {
      "@odata.type": "#microsoft.graph.iPv6CidrRange",
      "cidrAddress": "2001:db8::/32"
    }
  ],
  "locationMetadata": {
    "type": "Corporate",
    "description": "On-premises corporate network and VPN",
    "owner": "Network Team",
    "lastReviewDate": "2025-12-01"
  }
}
```

### Country/Region-Based Location
```json
{
  "@odata.type": "#microsoft.graph.countryNamedLocation",
  "displayName": "Allowed-Countries",
  "countriesAndRegions": [
    "US",
    "CA",
    "GB",
    "DE",
    "FR"
  ],
  "includeUnknownCountriesAndRegions": false,
  "locationMetadata": {
    "type": "Geo-Restriction",
    "description": "Approved countries for user access",
    "reviewFrequency": "Quarterly"
  }
}
```

### High-Risk Countries (Block List)
```json
{
  "@odata.type": "#microsoft.graph.countryNamedLocation",
  "displayName": "HighRisk-Countries",
  "countriesAndRegions": [
    "KP",
    "IR",
    "SY"
  ],
  "includeUnknownCountriesAndRegions": false,
  "locationMetadata": {
    "type": "Risk-Based",
    "description": "High-risk countries for blocking",
    "securityJustification": "Threat intelligence data"
  }
}
```

## Deployment Logic

### Phase 1: Pre-Deployment Validation

```powershell
function Validate-GroupConfiguration {
    param($Config)

    # Required fields
    if (-not $Config.displayName) {
        throw "displayName is required"
    }

    # Break-glass group specific validation
    if ($Config.displayName -match "EmergencyAccess|BreakGlass") {
        if ($Config.securityMetadata.criticality -ne "HIGH") {
            throw "Break-glass groups must have HIGH criticality"
        }
        if (-not $Config.securityMetadata.alertOnSignIn) {
            throw "Break-glass groups must have alertOnSignIn enabled"
        }
    }

    # Validate mailNickname (no spaces, special chars)
    if ($Config.mailNickname -match '[^a-z0-9-]') {
        throw "mailNickname can only contain lowercase letters, numbers, and hyphens"
    }

    return $true
}
```

### Phase 2: Idempotent Deployment

```powershell
function Deploy-EntraGroup {
    param(
        [Parameter(Mandatory)]
        [object]$Configuration,

        [switch]$WhatIf
    )

    try {
        # Check if group exists
        $existingGroup = Get-MgGroup -Filter "displayName eq '$($Configuration.displayName)'"

        if ($existingGroup) {
            Write-Host "  Group exists: $($Configuration.displayName)" -ForegroundColor Yellow

            if ($WhatIf) {
                Write-Host "  [WHAT-IF] Would update group: $($existingGroup.Id)" -ForegroundColor Cyan
                return @{ Status = "Skipped"; Id = $existingGroup.Id }
            }

            # Update group (only specific properties)
            $updateParams = @{
                Description = $Configuration.description
            }

            Update-MgGroup -GroupId $existingGroup.Id -BodyParameter $updateParams

            Write-Host "  Updated: $($Configuration.displayName)" -ForegroundColor Green
            return @{
                Status = "Updated"
                Id = $existingGroup.Id
                DisplayName = $Configuration.displayName
            }
        }
        else {
            if ($WhatIf) {
                Write-Host "  [WHAT-IF] Would create group: $($Configuration.displayName)" -ForegroundColor Cyan
                return @{ Status = "Skipped"; Id = $null }
            }

            # Create new group
            $groupParams = @{
                DisplayName = $Configuration.displayName
                Description = $Configuration.description
                MailEnabled = $false
                MailNickname = $Configuration.mailNickname
                SecurityEnabled = $true
                GroupTypes = @()
            }

            $newGroup = New-MgGroup -BodyParameter $groupParams

            Write-Host "  Created: $($Configuration.displayName) ($($newGroup.Id))" -ForegroundColor Green

            # Add initial members if specified
            if ($Configuration.initialMembers) {
                foreach ($member in $Configuration.initialMembers) {
                    Add-GroupMember -GroupId $newGroup.Id -MemberUpn $member
                }
            }

            return @{
                Status = "Created"
                Id = $newGroup.Id
                DisplayName = $Configuration.displayName
            }
        }
    }
    catch {
        Write-Error "Failed to deploy group $($Configuration.displayName): $_"
        return @{
            Status = "Failed"
            Id = $null
            Error = $_.Exception.Message
        }
    }
}
```

### Phase 3: Named Location Deployment

```powershell
function Deploy-NamedLocation {
    param(
        [Parameter(Mandatory)]
        [object]$Configuration,

        [switch]$WhatIf
    )

    try {
        # Check if named location exists
        $existingLocations = Get-MgIdentityConditionalAccessNamedLocation
        $existingLocation = $existingLocations | Where-Object { $_.DisplayName -eq $Configuration.displayName }

        if ($existingLocation) {
            Write-Host "  Named Location exists: $($Configuration.displayName)" -ForegroundColor Yellow

            if ($WhatIf) {
                Write-Host "  [WHAT-IF] Would update location: $($existingLocation.Id)" -ForegroundColor Cyan
                return @{ Status = "Skipped"; Id = $existingLocation.Id }
            }

            # Update location
            $updateParams = @{
                DisplayName = $Configuration.displayName
            }

            # Add type-specific properties
            if ($Configuration.'@odata.type' -eq '#microsoft.graph.ipNamedLocation') {
                $updateParams.IsTrusted = $Configuration.isTrusted
                $updateParams.IpRanges = $Configuration.ipRanges
            }
            elseif ($Configuration.'@odata.type' -eq '#microsoft.graph.countryNamedLocation') {
                $updateParams.CountriesAndRegions = $Configuration.countriesAndRegions
                $updateParams.IncludeUnknownCountriesAndRegions = $Configuration.includeUnknownCountriesAndRegions
            }

            Update-MgIdentityConditionalAccessNamedLocation -NamedLocationId $existingLocation.Id -BodyParameter $updateParams

            Write-Host "  Updated: $($Configuration.displayName)" -ForegroundColor Green
            return @{
                Status = "Updated"
                Id = $existingLocation.Id
                DisplayName = $Configuration.displayName
            }
        }
        else {
            if ($WhatIf) {
                Write-Host "  [WHAT-IF] Would create location: $($Configuration.displayName)" -ForegroundColor Cyan
                return @{ Status = "Skipped"; Id = $null }
            }

            # Create new named location
            $newLocation = New-MgIdentityConditionalAccessNamedLocation -BodyParameter $Configuration

            Write-Host "  Created: $($Configuration.displayName) ($($newLocation.Id))" -ForegroundColor Green
            return @{
                Status = "Created"
                Id = $newLocation.Id
                DisplayName = $Configuration.displayName
            }
        }
    }
    catch {
        Write-Error "Failed to deploy named location $($Configuration.displayName): $_"
        return @{
            Status = "Failed"
            Id = $null
            Error = $_.Exception.Message
        }
    }
}
```

## Output Mapping for Downstream Agents

After successful deployment, create object ID mapping file:

```powershell
function Export-ObjectMapping {
    param(
        [array]$GroupResults,
        [array]$LocationResults,
        [string]$OutputPath
    )

    $mapping = @{
        groups = @{}
        namedLocations = @{}
        timestamp = (Get-Date).ToString("o")
    }

    foreach ($result in $GroupResults) {
        if ($result.Status -in @("Created", "Updated")) {
            $mapping.groups[$result.DisplayName] = $result.Id
        }
    }

    foreach ($result in $LocationResults) {
        if ($result.Status -in @("Created", "Updated")) {
            $mapping.namedLocations[$result.DisplayName] = $result.Id
        }
    }

    $mapping | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8

    return $mapping
}
```

**Output Example**:
```json
{
  "groups": {
    "CA-Exclusion-EmergencyAccess": "00000000-0000-0000-0000-000000000001",
    "CA-Exclusion-ServiceAccounts": "00000000-0000-0000-0000-000000000002",
    "CA-Exclusion-BreakGlass": "00000000-0000-0000-0000-000000000003",
    "CA-Pilot-Users": "00000000-0000-0000-0000-000000000004"
  },
  "namedLocations": {
    "Corporate-Network": "00000000-0000-0000-0000-000000000010",
    "Allowed-Countries": "00000000-0000-0000-0000-000000000011",
    "HighRisk-Countries": "00000000-0000-0000-0000-000000000012"
  },
  "timestamp": "2025-12-11T14:30:22.000Z"
}
```

## Group Membership Management

### Add Members to Break-Glass Group

```powershell
function Add-BreakGlassAccount {
    param(
        [string]$GroupId,
        [string]$UserUpn
    )

    # Validate user exists
    $user = Get-MgUser -Filter "userPrincipalName eq '$UserUpn'"
    if (-not $user) {
        throw "User not found: $UserUpn"
    }

    # Add to group
    $memberParams = @{
        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
    }

    New-MgGroupMemberByRef -GroupId $GroupId -BodyParameter $memberParams

    # Log critical action
    Write-AuditLog -Action "BreakGlassAccountAdded" -GroupId $GroupId -UserId $user.Id -Severity "High"

    # Alert security team
    Send-SecurityAlert -Type "BreakGlassModification" -Details "Added $UserUpn to break-glass group"
}
```

### Remove Members (with Approval)

```powershell
function Remove-GroupMember {
    param(
        [string]$GroupId,
        [string]$UserId,
        [string]$Justification,
        [string]$ApprovedBy
    )

    # Get group info
    $group = Get-MgGroup -GroupId $GroupId

    # Extra validation for break-glass groups
    if ($group.DisplayName -match "EmergencyAccess|BreakGlass") {
        if (-not $ApprovedBy) {
            throw "Break-glass group modifications require approval"
        }

        # Verify minimum members remain
        $members = Get-MgGroupMember -GroupId $GroupId
        if ($members.Count -le 2) {
            throw "Cannot remove member: Break-glass groups must have at least 2 members"
        }
    }

    # Remove member
    Remove-MgGroupMemberByRef -GroupId $GroupId -DirectoryObjectId $UserId

    # Audit log
    Write-AuditLog -Action "GroupMemberRemoved" -GroupId $GroupId -UserId $UserId `
        -Justification $Justification -ApprovedBy $ApprovedBy -Severity "High"
}
```

## Security Features

### 1. Break-Glass Group Monitoring

```powershell
function Enable-BreakGlassMonitoring {
    param([string]$GroupId)

    # Create alert rule for any sign-in from break-glass accounts
    $alertRule = @{
        displayName = "Break-Glass Account Sign-In Detected"
        severity = "Critical"
        condition = "SignIn from member of $GroupId"
        notificationChannels = @("Security Team Email", "Security Team SMS", "SIEM")
        autoResponse = @{
            createIncident = $true
            notifyOnCall = $true
        }
    }

    # Deploy via Azure Monitor (pseudo-code)
    New-AlertRule -Rule $alertRule
}
```

### 2. Membership Change Alerts

```powershell
function Watch-CriticalGroupChanges {
    param([array]$GroupIds)

    foreach ($groupId in $GroupIds) {
        # Subscribe to group membership changes
        $subscription = @{
            changeType = "updated"
            resource = "/groups/$groupId/members"
            notificationUrl = "https://security-webhook.company.com/group-change"
            expirationDateTime = (Get-Date).AddMonths(3).ToString("o")
        }

        New-MgSubscription -BodyParameter $subscription
    }
}
```

### 3. Access Reviews for Exclusion Groups

```powershell
function Start-GroupAccessReview {
    param(
        [string]$GroupId,
        [string]$ReviewFrequency = "Quarterly"  # Monthly, Quarterly, Annually
    )

    $accessReview = @{
        displayName = "Conditional Access Exclusion Group Review"
        scope = @{
            query = "/groups/$GroupId/members"
            queryType = "MicrosoftGraph"
        }
        reviewers = @(
            @{
                query = "/users/{security-admin-id}"
                queryType = "MicrosoftGraph"
            }
        )
        settings = @{
            recurrence = @{
                pattern = @{
                    type = $ReviewFrequency
                }
            }
            autoApplyDecisionsEnabled = $false
            defaultDecisionEnabled = $false
        }
    }

    # Create via Microsoft Entra ID Governance (pseudo-code)
    New-AccessReviewScheduleDefinition -BodyParameter $accessReview
}
```

## Validation & Testing

### Validate Break-Glass Group Configuration

```powershell
function Test-BreakGlassGroupCompliance {
    param([string]$GroupId)

    $group = Get-MgGroup -GroupId $GroupId
    $members = Get-MgGroupMember -GroupId $GroupId

    $issues = @()

    # Check member count
    if ($members.Count -lt 2) {
        $issues += "Break-glass group must have at least 2 members (found: $($members.Count))"
    }

    if ($members.Count -gt 5) {
        $issues += "Break-glass group should not exceed 5 members (found: $($members.Count))"
    }

    # Check monitoring
    if (-not (Test-GroupMonitoringEnabled -GroupId $GroupId)) {
        $issues += "Sign-in monitoring not enabled for break-glass group"
    }

    # Check CA policy exclusions
    $caPolicies = Get-MgIdentityConditionalAccessPolicy
    foreach ($policy in $caPolicies) {
        if ($policy.Conditions.Users.ExcludeGroups -notcontains $GroupId) {
            $issues += "CA policy '$($policy.DisplayName)' does not exclude break-glass group"
        }
    }

    return @{
        Compliant = ($issues.Count -eq 0)
        Issues = $issues
        MemberCount = $members.Count
    }
}
```

### Validate Named Location IP Ranges

```powershell
function Test-NamedLocationIPRanges {
    param([string]$LocationId)

    $location = Get-MgIdentityConditionalAccessNamedLocation -NamedLocationId $LocationId

    if ($location.AdditionalProperties.'@odata.type' -ne '#microsoft.graph.ipNamedLocation') {
        return @{ Valid = $true; Type = "Country" }
    }

    $issues = @()

    foreach ($ipRange in $location.IpRanges) {
        try {
            # Validate CIDR notation
            if ($ipRange.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.iPv4CidrRange') {
                if ($ipRange.CidrAddress -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$') {
                    $issues += "Invalid IPv4 CIDR: $($ipRange.CidrAddress)"
                }
            }
            elseif ($ipRange.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.iPv6CidrRange') {
                # IPv6 validation (simplified)
                if ($ipRange.CidrAddress -notmatch ':') {
                    $issues += "Invalid IPv6 CIDR: $($ipRange.CidrAddress)"
                }
            }
        }
        catch {
            $issues += "Error validating IP range: $($ipRange.CidrAddress)"
        }
    }

    return @{
        Valid = ($issues.Count -eq 0)
        Issues = $issues
        RangeCount = $location.IpRanges.Count
    }
}
```

## Best Practices

1. **Break-Glass Groups**
   - Minimum 2 members, maximum 5
   - Cloud-only accounts (not synced from on-premises)
   - FIDO2 security keys for authentication (no passwords)
   - Monitor ALL sign-ins with real-time alerts
   - Quarterly access reviews
   - Annual credential rotation
   - Excluded from ALL CA policies

2. **Service Account Exclusions**
   - Use Conditional Access for Workload Identities instead (preferred)
   - If user-based service accounts exist, migrate to Managed Identities
   - If migration not possible, use separate exclusion group
   - Monitor for unusual activity
   - Monthly access reviews

3. **Named Locations**
   - Keep IP ranges up to date
   - Document network changes
   - Review quarterly
   - Use trusted locations sparingly (security risk)
   - Prefer MFA over trusted location bypass

4. **Group Lifecycle**
   - Validate configurations before deployment
   - Use descriptive names (CA-Exclusion-*, CA-Pilot-*)
   - Document purpose in description field
   - Set ownership (security team)
   - Regular access reviews

5. **Monitoring**
   - Alert on break-glass group changes
   - Monitor break-glass account sign-ins
   - Track group membership changes
   - Review access regularly
   - Integration with SIEM

## Troubleshooting

### Group Already Exists Error

```powershell
# Error: Group with mailNickname already exists
# Solution: Use different mailNickname or update existing group

$existingGroup = Get-MgGroup -Filter "mailNickname eq 'ca-exclusion-emergency'"
if ($existingGroup) {
    # Update existing group instead
    Update-MgGroup -GroupId $existingGroup.Id -BodyParameter $updateParams
}
```

### Named Location Not Appearing in CA Policy UI

```powershell
# Issue: Newly created named location not visible
# Solution: Wait 5-10 minutes for replication, then refresh

Start-Sleep -Seconds 300
$location = Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq 'Corporate-Network'"
```

### Insufficient Permissions Error

```powershell
# Error: Insufficient privileges to complete the operation
# Solution: Verify required permissions

$context = Get-MgContext
Write-Host "Current scopes: $($context.Scopes -join ', ')"

# Required scopes:
# - Group.ReadWrite.All
# - Policy.ReadWrite.ConditionalAccess
```

## Rollback Procedures

```powershell
function Rollback-GroupDeployment {
    param(
        [string]$BackupFilePath,
        [switch]$DeleteNewGroups,
        [switch]$RestoreMembership
    )

    $backup = Get-Content $BackupFilePath | ConvertFrom-Json

    foreach ($group in $backup.groups) {
        $currentGroup = Get-MgGroup -Filter "displayName eq '$($group.displayName)'"

        if ($DeleteNewGroups -and $group.wasCreated) {
            # Delete newly created group
            Remove-MgGroup -GroupId $currentGroup.Id
            Write-Host "Deleted: $($group.displayName)"
        }
        elseif ($RestoreMembership) {
            # Restore original membership
            # Remove current members
            $currentMembers = Get-MgGroupMember -GroupId $currentGroup.Id
            foreach ($member in $currentMembers) {
                Remove-MgGroupMemberByRef -GroupId $currentGroup.Id -DirectoryObjectId $member.Id
            }

            # Add original members back
            foreach ($memberId in $group.originalMembers) {
                $memberParams = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$memberId" }
                New-MgGroupMemberByRef -GroupId $currentGroup.Id -BodyParameter $memberParams
            }

            Write-Host "Restored membership: $($group.displayName)"
        }
    }
}
```
