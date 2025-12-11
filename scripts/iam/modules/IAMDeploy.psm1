#Requires -Version 7.0

<#
.SYNOPSIS
    PowerShell module for deploying and managing Microsoft Entra ID IAM configurations.

.DESCRIPTION
    Provides functions for deploying:
    - Entra ID security groups
    - Named Locations
    - Conditional Access policies
    - Service Principals
    - SSO integrations

    Security-first design with:
    - Break-glass account protection
    - Audit logging
    - Approval workflows
    - Rollback capabilities

.NOTES
    Requires Microsoft.Graph PowerShell SDK modules:
    - Microsoft.Graph.Authentication
    - Microsoft.Graph.Groups
    - Microsoft.Graph.Identity.SignIns
    - Microsoft.Graph.Applications
#>

#region Module Variables

$script:ModuleVersion = "1.0.0"
$script:ObjectIdMapping = @{
    groups = @{}
    namedLocations = @{}
}
$script:AuditLogPath = Join-Path $PSScriptRoot "../logs/iam-audit.log"

#endregion

#region Connection Management

function Test-IAMGraphConnection {
    <#
    .SYNOPSIS
        Tests if connected to Microsoft Graph with required permissions.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $context = Get-MgContext
        if ($null -eq $context) {
            Write-Warning "Not connected to Microsoft Graph"
            return $false
        }

        Write-Verbose "Connected to tenant: $($context.TenantId)"
        Write-Verbose "Account: $($context.Account)"
        Write-Verbose "Scopes: $($context.Scopes -join ', ')"

        return $true
    }
    catch {
        Write-Warning "Error checking Graph connection: $_"
        return $false
    }
}

function Connect-IAMGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with required IAM permissions.
    #>
    [CmdletBinding()]
    param(
        [string[]]$AdditionalScopes = @()
    )

    $requiredScopes = @(
        "Group.ReadWrite.All",
        "Policy.ReadWrite.ConditionalAccess",
        "Application.ReadWrite.All",
        "Directory.ReadWrite.All",
        "AuditLog.Read.All"
    )

    $scopes = $requiredScopes + $AdditionalScopes | Select-Object -Unique

    try {
        Connect-MgGraph -Scopes $scopes -NoWelcome

        $context = Get-MgContext
        Write-Host "Connected to Microsoft Graph" -ForegroundColor Green
        Write-Host "  Tenant: $($context.TenantId)" -ForegroundColor Cyan
        Write-Host "  Account: $($context.Account)" -ForegroundColor Cyan

        return $true
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        return $false
    }
}

#endregion

#region Configuration Reading

function Read-IAMConfigurationFile {
    <#
    .SYNOPSIS
        Reads and parses a JSON configuration file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$Path
    )

    try {
        $content = Get-Content -Path $Path -Raw -Encoding UTF8

        # Handle UTF-16 encoded files (common from Graph exports)
        if ($content[0] -eq [char]0xFF -and $content[1] -eq [char]0xFE) {
            $content = Get-Content -Path $Path -Raw -Encoding Unicode
        }

        $config = $content | ConvertFrom-Json

        return $config
    }
    catch {
        Write-Error "Failed to read configuration file '$Path': $_"
        throw
    }
}

#endregion

#region Audit Logging

function Write-IAMAuditLog {
    <#
    .SYNOPSIS
        Writes audit log entry for IAM operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("GroupCreated", "GroupUpdated", "LocationCreated", "LocationUpdated",
                     "CAPolicyCreated", "CAPolicyUpdated", "CAPolicyDisabled",
                     "ServicePrincipalCreated", "BreakGlassModification")]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$ResourceName,

        [string]$ResourceId,
        [string]$Details,
        [ValidateSet("Info", "Warning", "Critical")]
        [string]$Severity = "Info"
    )

    $logDir = Split-Path -Parent $script:AuditLogPath
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    $context = Get-MgContext
    $logEntry = @{
        timestamp = (Get-Date).ToString("o")
        action = $Action
        operator = $context.Account
        tenantId = $context.TenantId
        resourceName = $ResourceName
        resourceId = $ResourceId
        details = $Details
        severity = $Severity
    }

    $logEntry | ConvertTo-Json -Compress | Out-File -FilePath $script:AuditLogPath -Append -Encoding UTF8

    Write-Verbose "Audit log: $Action - $ResourceName"
}

#endregion

#region Groups

function Deploy-EntraGroup {
    <#
    .SYNOPSIS
        Deploys an Entra ID security group.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration,

        [switch]$WhatIf
    )

    try {
        # Validate configuration
        if (-not $Configuration.displayName) {
            throw "displayName is required"
        }

        if (-not $Configuration.mailNickname) {
            throw "mailNickname is required"
        }

        # Check if group exists
        $existingGroup = Get-MgGroup -Filter "displayName eq '$($Configuration.displayName)'" -ErrorAction SilentlyContinue

        if ($existingGroup) {
            Write-Host "  Group exists: $($Configuration.displayName)" -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess($Configuration.displayName, "Update group")) {
                # Update description only (safe property)
                $updateParams = @{
                    Description = $Configuration.description
                }

                Update-MgGroup -GroupId $existingGroup.Id -BodyParameter $updateParams

                Write-Host "  Updated: $($Configuration.displayName)" -ForegroundColor Green

                Write-IAMAuditLog -Action "GroupUpdated" -ResourceName $Configuration.displayName -ResourceId $existingGroup.Id

                return @{
                    Status = "Updated"
                    Id = $existingGroup.Id
                    DisplayName = $Configuration.displayName
                }
            }
            else {
                return @{ Status = "Skipped"; Id = $existingGroup.Id }
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess($Configuration.displayName, "Create group")) {
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

                Write-IAMAuditLog -Action "GroupCreated" -ResourceName $Configuration.displayName -ResourceId $newGroup.Id

                # Store in mapping
                $script:ObjectIdMapping.groups[$Configuration.displayName] = $newGroup.Id

                return @{
                    Status = "Created"
                    Id = $newGroup.Id
                    DisplayName = $Configuration.displayName
                }
            }
            else {
                return @{ Status = "Skipped"; Id = $null }
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

#endregion

#region Named Locations

function Deploy-NamedLocation {
    <#
    .SYNOPSIS
        Deploys a Named Location for Conditional Access.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration,

        [switch]$WhatIf
    )

    try {
        # Validate configuration
        if (-not $Configuration.displayName) {
            throw "displayName is required"
        }

        # Check if location exists
        $existingLocations = Get-MgIdentityConditionalAccessNamedLocation -ErrorAction SilentlyContinue
        $existingLocation = $existingLocations | Where-Object { $_.DisplayName -eq $Configuration.displayName }

        if ($existingLocation) {
            Write-Host "  Named Location exists: $($Configuration.displayName)" -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess($Configuration.displayName, "Update named location")) {
                # Update location
                Update-MgIdentityConditionalAccessNamedLocation -NamedLocationId $existingLocation.Id -BodyParameter $Configuration

                Write-Host "  Updated: $($Configuration.displayName)" -ForegroundColor Green

                Write-IAMAuditLog -Action "LocationUpdated" -ResourceName $Configuration.displayName -ResourceId $existingLocation.Id

                return @{
                    Status = "Updated"
                    Id = $existingLocation.Id
                    DisplayName = $Configuration.displayName
                }
            }
            else {
                return @{ Status = "Skipped"; Id = $existingLocation.Id }
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess($Configuration.displayName, "Create named location")) {
                # Create new named location
                $newLocation = New-MgIdentityConditionalAccessNamedLocation -BodyParameter $Configuration

                Write-Host "  Created: $($Configuration.displayName) ($($newLocation.Id))" -ForegroundColor Green

                Write-IAMAuditLog -Action "LocationCreated" -ResourceName $Configuration.displayName -ResourceId $newLocation.Id

                # Store in mapping
                $script:ObjectIdMapping.namedLocations[$Configuration.displayName] = $newLocation.Id

                return @{
                    Status = "Created"
                    Id = $newLocation.Id
                    DisplayName = $Configuration.displayName
                }
            }
            else {
                return @{ Status = "Skipped"; Id = $null }
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

#endregion

#region Conditional Access Policies

function Validate-ConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Validates a Conditional Access policy configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Policy
    )

    $issues = @()

    # Display name required
    if (-not $Policy.displayName) {
        $issues += "displayName is required"
    }

    # CRITICAL: Break-glass exclusions required
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

    # At least one condition required
    if (-not ($Policy.conditions.users -or $Policy.conditions.applications)) {
        $issues += "At least one condition (users or applications) is required"
    }

    # At least one control required
    if (-not ($Policy.grantControls -or $Policy.sessionControls)) {
        $issues += "At least one control (grant or session) is required"
    }

    return @{
        Valid = ($issues.Count -eq 0)
        Issues = $issues
    }
}

function Resolve-PolicyPlaceholders {
    <#
    .SYNOPSIS
        Resolves {{GroupId:name}} and {{NamedLocationId:name}} placeholders.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Policy
    )

    $resolvedPolicy = $Policy | ConvertTo-Json -Depth 10 | ConvertFrom-Json

    # Resolve Group ID placeholders
    if ($resolvedPolicy.conditions.users.excludeGroups) {
        $resolvedGroups = @()
        foreach ($group in $resolvedPolicy.conditions.users.excludeGroups) {
            if ($group -match '{{GroupId:(.+?)}}') {
                $groupName = $matches[1]
                if ($script:ObjectIdMapping.groups.ContainsKey($groupName)) {
                    $resolvedGroups += $script:ObjectIdMapping.groups[$groupName]
                    Write-Verbose "Resolved group placeholder: $groupName → $($script:ObjectIdMapping.groups[$groupName])"
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
                    if ($script:ObjectIdMapping.namedLocations.ContainsKey($locationName)) {
                        $resolvedLocations += $script:ObjectIdMapping.namedLocations[$locationName]
                        Write-Verbose "Resolved location placeholder: $locationName → $($script:ObjectIdMapping.namedLocations[$locationName])"
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

function Deploy-ConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Deploys a Conditional Access policy.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration,

        [ValidateSet("enabledForReportingButNotEnforced", "enabled", "disabled")]
        [string]$InitialState = "enabledForReportingButNotEnforced",

        [switch]$WhatIf
    )

    try {
        # 1. Validate policy
        $validation = Validate-ConditionalAccessPolicy -Policy $Configuration
        if (-not $validation.Valid) {
            throw "Validation failed: $($validation.Issues -join '; ')"
        }

        # 2. Resolve placeholders
        $resolvedPolicy = Resolve-PolicyPlaceholders -Policy $Configuration

        # 3. Override state if specified
        if ($InitialState) {
            $resolvedPolicy.state = $InitialState
        }

        # 4. Check if policy exists
        $existingPolicies = Get-MgIdentityConditionalAccessPolicy -ErrorAction SilentlyContinue
        $existingPolicy = $existingPolicies | Where-Object { $_.DisplayName -eq $resolvedPolicy.displayName }

        if ($existingPolicy) {
            Write-Host "  Policy exists: $($resolvedPolicy.displayName)" -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess($resolvedPolicy.displayName, "Update CA policy")) {
                # Backup before update
                $backupPath = Join-Path $PSScriptRoot "../backups/ca-policies"
                if (-not (Test-Path $backupPath)) {
                    New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
                }

                $backupFile = Join-Path $backupPath "$($existingPolicy.Id)-$(Get-Date -Format 'yyyyMMddHHmmss').json"
                $existingPolicy | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupFile -Encoding UTF8

                # Update policy
                Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existingPolicy.Id -BodyParameter $resolvedPolicy

                Write-Host "  Updated: $($resolvedPolicy.displayName) (State: $($resolvedPolicy.state))" -ForegroundColor Green

                Write-IAMAuditLog -Action "CAPolicyUpdated" -ResourceName $resolvedPolicy.displayName -ResourceId $existingPolicy.Id `
                    -Details "State: $($resolvedPolicy.state)" -Severity "Warning"

                return @{
                    Status = "Updated"
                    Id = $existingPolicy.Id
                    DisplayName = $resolvedPolicy.displayName
                    State = $resolvedPolicy.state
                }
            }
            else {
                return @{ Status = "Skipped"; Id = $existingPolicy.Id }
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess($resolvedPolicy.displayName, "Create CA policy")) {
                # Create new policy
                $newPolicy = New-MgIdentityConditionalAccessPolicy -BodyParameter $resolvedPolicy

                Write-Host "  Created: $($resolvedPolicy.displayName) ($($newPolicy.Id))" -ForegroundColor Green
                Write-Host "  State: $($resolvedPolicy.state)" -ForegroundColor Cyan

                Write-IAMAuditLog -Action "CAPolicyCreated" -ResourceName $resolvedPolicy.displayName -ResourceId $newPolicy.Id `
                    -Details "State: $($resolvedPolicy.state)" -Severity "Critical"

                return @{
                    Status = "Created"
                    Id = $newPolicy.Id
                    DisplayName = $resolvedPolicy.displayName
                    State = $resolvedPolicy.state
                }
            }
            else {
                return @{ Status = "Skipped"; Id = $null }
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

#endregion

#region Object ID Mapping

function Export-ObjectIdMapping {
    <#
    .SYNOPSIS
        Exports the object ID mapping to a JSON file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $mapping = @{
        groups = $script:ObjectIdMapping.groups
        namedLocations = $script:ObjectIdMapping.namedLocations
        timestamp = (Get-Date).ToString("o")
    }

    $mapping | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8

    Write-Verbose "Object ID mapping exported to: $OutputPath"

    return $mapping
}

function Import-ObjectIdMapping {
    <#
    .SYNOPSIS
        Imports object ID mapping from a JSON file or Graph API.
    #>
    [CmdletBinding()]
    param(
        [string]$FilePath
    )

    if ($FilePath -and (Test-Path $FilePath)) {
        # Import from file
        $mapping = Get-Content $FilePath -Raw | ConvertFrom-Json
        $script:ObjectIdMapping.groups = $mapping.groups
        $script:ObjectIdMapping.namedLocations = $mapping.namedLocations

        Write-Verbose "Object ID mapping imported from file: $FilePath"
    }
    else {
        # Query from Graph API
        Write-Verbose "Querying object IDs from Microsoft Graph..."

        # Get all groups starting with "CA-"
        $groups = Get-MgGroup -Filter "startswith(displayName, 'CA-')" -All -ErrorAction SilentlyContinue
        foreach ($group in $groups) {
            $script:ObjectIdMapping.groups[$group.DisplayName] = $group.Id
        }

        # Get all named locations
        $locations = Get-MgIdentityConditionalAccessNamedLocation -All -ErrorAction SilentlyContinue
        foreach ($location in $locations) {
            $script:ObjectIdMapping.namedLocations[$location.DisplayName] = $location.Id
        }

        Write-Verbose "Object ID mapping loaded from Graph API"
        Write-Verbose "  Groups: $($script:ObjectIdMapping.groups.Count)"
        Write-Verbose "  Named Locations: $($script:ObjectIdMapping.namedLocations.Count)"
    }

    return $script:ObjectIdMapping
}

#endregion

#region Exports

Export-ModuleMember -Function @(
    'Test-IAMGraphConnection',
    'Connect-IAMGraph',
    'Read-IAMConfigurationFile',
    'Write-IAMAuditLog',
    'Deploy-EntraGroup',
    'Deploy-NamedLocation',
    'Validate-ConditionalAccessPolicy',
    'Resolve-PolicyPlaceholders',
    'Deploy-ConditionalAccessPolicy',
    'Export-ObjectIdMapping',
    'Import-ObjectIdMapping'
)

#endregion
