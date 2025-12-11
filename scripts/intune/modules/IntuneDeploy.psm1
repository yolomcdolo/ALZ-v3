#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Identity.SignIns

<#
.SYNOPSIS
    Intune Deployment Module - Core functions for deploying Intune configurations.

.DESCRIPTION
    This module provides functions for deploying Microsoft Intune configurations
    using the Microsoft Graph API. It supports:
    - Entra ID Groups and Named Locations
    - Conditional Access Policies
    - Device Compliance Policies
    - Windows Update Rings
    - App Protection Policies

.NOTES
    Author: ALZ-v3 Project
    Version: 1.0.0
    Requires: Microsoft.Graph PowerShell SDK
#>

# Module-level variables
$Script:GraphConnected = $false
$Script:IdentityCache = @{
    Groups = @{}
    NamedLocations = @{}
}

#region Authentication

function Connect-IntuneGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with required scopes for Intune deployment.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$AdditionalScopes = @()
    )

    $requiredScopes = @(
        "Group.ReadWrite.All",
        "Policy.ReadWrite.ConditionalAccess",
        "Policy.Read.All",
        "DeviceManagementConfiguration.ReadWrite.All",
        "DeviceManagementApps.ReadWrite.All",
        "Directory.Read.All"
    )

    $allScopes = $requiredScopes + $AdditionalScopes | Select-Object -Unique

    try {
        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
        Connect-MgGraph -Scopes $allScopes -NoWelcome

        $context = Get-MgContext
        if ($null -eq $context) {
            throw "Failed to connect to Microsoft Graph"
        }

        Write-Host "Connected as: $($context.Account)" -ForegroundColor Green
        Write-Host "Tenant: $($context.TenantId)" -ForegroundColor Green

        $Script:GraphConnected = $true
        return $true
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        return $false
    }
}

function Test-IntuneGraphConnection {
    <#
    .SYNOPSIS
        Tests if connected to Microsoft Graph.
    #>
    [CmdletBinding()]
    param()

    if (-not $Script:GraphConnected) {
        $context = Get-MgContext
        $Script:GraphConnected = ($null -ne $context)
    }

    return $Script:GraphConnected
}

#endregion

#region Helper Functions

function Read-ConfigurationFile {
    <#
    .SYNOPSIS
        Reads a JSON configuration file, handling UTF-16 encoding.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Configuration file not found: $Path"
    }

    try {
        # Read raw bytes to detect encoding
        $bytes = [System.IO.File]::ReadAllBytes($Path)

        # Check for BOM and determine encoding
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
            # UTF-16 LE
            $content = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
        }
        elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
            # UTF-16 BE
            $content = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
        }
        else {
            # Assume UTF-8
            $content = [System.Text.Encoding]::UTF8.GetString($bytes)
        }

        # Parse JSON
        $config = $content | ConvertFrom-Json -Depth 20
        return $config
    }
    catch {
        throw "Failed to read configuration file '$Path': $_"
    }
}

function Resolve-Placeholders {
    <#
    .SYNOPSIS
        Resolves placeholders in configuration objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration
    )

    $json = $Configuration | ConvertTo-Json -Depth 20

    # Resolve Group ID placeholders
    $pattern = '\{\{GroupId:([^}]+)\}\}'
    $matches = [regex]::Matches($json, $pattern)
    foreach ($match in $matches) {
        $groupName = $match.Groups[1].Value
        if ($Script:IdentityCache.Groups.ContainsKey($groupName)) {
            $json = $json.Replace($match.Value, $Script:IdentityCache.Groups[$groupName])
        }
        else {
            Write-Warning "Group not found in cache: $groupName"
        }
    }

    # Resolve Named Location ID placeholders
    $pattern = '\{\{NamedLocationId:([^}]+)\}\}'
    $matches = [regex]::Matches($json, $pattern)
    foreach ($match in $matches) {
        $locationName = $match.Groups[1].Value
        if ($Script:IdentityCache.NamedLocations.ContainsKey($locationName)) {
            $json = $json.Replace($match.Value, $Script:IdentityCache.NamedLocations[$locationName])
        }
        else {
            Write-Warning "Named Location not found in cache: $locationName"
        }
    }

    return $json | ConvertFrom-Json -Depth 20
}

function Invoke-GraphRequestWithRetry {
    <#
    .SYNOPSIS
        Invokes a Graph API request with retry logic for throttling.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [int]$MaxRetries = 3
    )

    $retryCount = 0
    $baseDelay = 5

    while ($retryCount -lt $MaxRetries) {
        try {
            $params = @{
                Method = $Method
                Uri = $Uri
            }

            if ($Body) {
                $params.Body = $Body | ConvertTo-Json -Depth 20
                $params.ContentType = "application/json"
            }

            $response = Invoke-MgGraphRequest @params
            return $response
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__

            if ($statusCode -eq 429 -or $statusCode -eq 503) {
                $retryCount++
                $delay = $baseDelay * [Math]::Pow(2, $retryCount)
                Write-Warning "API throttled. Retrying in $delay seconds... (Attempt $retryCount of $MaxRetries)"
                Start-Sleep -Seconds $delay
            }
            else {
                throw
            }
        }
    }

    throw "Maximum retries exceeded for $Uri"
}

#endregion

#region Group Deployment

function Deploy-EntraGroup {
    <#
    .SYNOPSIS
        Deploys an Entra ID security group.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration
    )

    $displayName = $Configuration.displayName

    try {
        # Check if group exists
        $existingGroup = Get-MgGroup -Filter "displayName eq '$displayName'" -ErrorAction SilentlyContinue

        if ($existingGroup) {
            Write-Host "  Updating existing group: $displayName" -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess($displayName, "Update Group")) {
                $updateBody = @{
                    description = $Configuration.description
                }
                Update-MgGroup -GroupId $existingGroup.Id -BodyParameter $updateBody
                $Script:IdentityCache.Groups[$displayName] = $existingGroup.Id
                return @{ Status = "Updated"; Id = $existingGroup.Id }
            }
        }
        else {
            Write-Host "  Creating new group: $displayName" -ForegroundColor Green

            if ($PSCmdlet.ShouldProcess($displayName, "Create Group")) {
                $newGroup = New-MgGroup -BodyParameter @{
                    displayName = $displayName
                    description = $Configuration.description
                    mailEnabled = $false
                    mailNickname = ($displayName -replace '[^a-zA-Z0-9]', '').ToLower()
                    securityEnabled = $true
                    groupTypes = @()
                }
                $Script:IdentityCache.Groups[$displayName] = $newGroup.Id
                return @{ Status = "Created"; Id = $newGroup.Id }
            }
        }
    }
    catch {
        Write-Error "Failed to deploy group '$displayName': $_"
        return @{ Status = "Failed"; Error = $_.Exception.Message }
    }

    return @{ Status = "Skipped" }
}

#endregion

#region Named Location Deployment

function Deploy-NamedLocation {
    <#
    .SYNOPSIS
        Deploys a Named Location for Conditional Access.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration
    )

    $displayName = $Configuration.displayName

    try {
        # Check if location exists
        $existingLocation = Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq '$displayName'" -ErrorAction SilentlyContinue

        if ($existingLocation) {
            Write-Host "  Updating existing named location: $displayName" -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess($displayName, "Update Named Location")) {
                Update-MgIdentityConditionalAccessNamedLocation -NamedLocationId $existingLocation.Id -BodyParameter $Configuration
                $Script:IdentityCache.NamedLocations[$displayName] = $existingLocation.Id
                return @{ Status = "Updated"; Id = $existingLocation.Id }
            }
        }
        else {
            Write-Host "  Creating new named location: $displayName" -ForegroundColor Green

            if ($PSCmdlet.ShouldProcess($displayName, "Create Named Location")) {
                $newLocation = New-MgIdentityConditionalAccessNamedLocation -BodyParameter $Configuration
                $Script:IdentityCache.NamedLocations[$displayName] = $newLocation.Id
                return @{ Status = "Created"; Id = $newLocation.Id }
            }
        }
    }
    catch {
        Write-Error "Failed to deploy named location '$displayName': $_"
        return @{ Status = "Failed"; Error = $_.Exception.Message }
    }

    return @{ Status = "Skipped" }
}

#endregion

#region Conditional Access Deployment

function Deploy-ConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Deploys a Conditional Access policy.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration,

        [Parameter()]
        [ValidateSet("enabled", "disabled", "enabledForReportingButNotEnforced")]
        [string]$InitialState = "enabledForReportingButNotEnforced"
    )

    # Resolve placeholders
    $resolvedConfig = Resolve-Placeholders -Configuration $Configuration
    $displayName = $resolvedConfig.displayName

    # Override state if specified
    if ($InitialState) {
        $resolvedConfig.state = $InitialState
    }

    try {
        # Check if policy exists
        $existingPolicy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$displayName'" -ErrorAction SilentlyContinue

        if ($existingPolicy) {
            Write-Host "  Updating existing CA policy: $displayName" -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess($displayName, "Update Conditional Access Policy")) {
                Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existingPolicy.Id -BodyParameter $resolvedConfig
                return @{ Status = "Updated"; Id = $existingPolicy.Id }
            }
        }
        else {
            Write-Host "  Creating new CA policy: $displayName" -ForegroundColor Green

            if ($PSCmdlet.ShouldProcess($displayName, "Create Conditional Access Policy")) {
                $newPolicy = New-MgIdentityConditionalAccessPolicy -BodyParameter $resolvedConfig
                return @{ Status = "Created"; Id = $newPolicy.Id }
            }
        }
    }
    catch {
        Write-Error "Failed to deploy CA policy '$displayName': $_"
        return @{ Status = "Failed"; Error = $_.Exception.Message }
    }

    return @{ Status = "Skipped" }
}

#endregion

#region Compliance Policy Deployment

function Deploy-CompliancePolicy {
    <#
    .SYNOPSIS
        Deploys a device compliance policy.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration
    )

    $displayName = $Configuration.displayName
    $odataType = $Configuration.'@odata.type'

    try {
        # Check if policy exists
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies?`$filter=displayName eq '$displayName'"
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri
        $existingPolicy = $response.value | Where-Object { $_.displayName -eq $displayName } | Select-Object -First 1

        if ($existingPolicy) {
            Write-Host "  Updating existing compliance policy: $displayName" -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess($displayName, "Update Compliance Policy")) {
                $updateUri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies/$($existingPolicy.id)"

                # Remove read-only properties for update
                $updateConfig = $Configuration | Select-Object -Property * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version

                Invoke-GraphRequestWithRetry -Method PATCH -Uri $updateUri -Body $updateConfig
                return @{ Status = "Updated"; Id = $existingPolicy.id }
            }
        }
        else {
            Write-Host "  Creating new compliance policy: $displayName" -ForegroundColor Green

            if ($PSCmdlet.ShouldProcess($displayName, "Create Compliance Policy")) {
                $createUri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies"
                $response = Invoke-GraphRequestWithRetry -Method POST -Uri $createUri -Body $Configuration
                return @{ Status = "Created"; Id = $response.id }
            }
        }
    }
    catch {
        Write-Error "Failed to deploy compliance policy '$displayName': $_"
        return @{ Status = "Failed"; Error = $_.Exception.Message }
    }

    return @{ Status = "Skipped" }
}

#endregion

#region Update Ring Deployment

function Deploy-WindowsUpdateRing {
    <#
    .SYNOPSIS
        Deploys a Windows Update for Business ring.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration
    )

    $displayName = $Configuration.displayName

    try {
        # Check if ring exists
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations?`$filter=displayName eq '$displayName'"
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri
        $existingRing = $response.value | Where-Object { $_.displayName -eq $displayName -and $_.'@odata.type' -eq '#microsoft.graph.windowsUpdateForBusinessConfiguration' } | Select-Object -First 1

        if ($existingRing) {
            Write-Host "  Updating existing update ring: $displayName" -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess($displayName, "Update Windows Update Ring")) {
                $updateUri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/$($existingRing.id)"
                $updateConfig = $Configuration | Select-Object -Property * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version

                Invoke-GraphRequestWithRetry -Method PATCH -Uri $updateUri -Body $updateConfig
                return @{ Status = "Updated"; Id = $existingRing.id }
            }
        }
        else {
            Write-Host "  Creating new update ring: $displayName" -ForegroundColor Green

            if ($PSCmdlet.ShouldProcess($displayName, "Create Windows Update Ring")) {
                $createUri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations"
                $response = Invoke-GraphRequestWithRetry -Method POST -Uri $createUri -Body $Configuration
                return @{ Status = "Created"; Id = $response.id }
            }
        }
    }
    catch {
        Write-Error "Failed to deploy update ring '$displayName': $_"
        return @{ Status = "Failed"; Error = $_.Exception.Message }
    }

    return @{ Status = "Skipped" }
}

function Deploy-DriverUpdateProfile {
    <#
    .SYNOPSIS
        Deploys a Driver Update profile.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration
    )

    $displayName = $Configuration.displayName

    try {
        # Check if profile exists
        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles?`$filter=displayName eq '$displayName'"
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri
        $existingProfile = $response.value | Where-Object { $_.displayName -eq $displayName } | Select-Object -First 1

        if ($existingProfile) {
            Write-Host "  Updating existing driver update profile: $displayName" -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess($displayName, "Update Driver Update Profile")) {
                $updateUri = "https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles/$($existingProfile.id)"
                $updateConfig = $Configuration | Select-Object -Property * -ExcludeProperty id, createdDateTime, lastModifiedDateTime

                Invoke-GraphRequestWithRetry -Method PATCH -Uri $updateUri -Body $updateConfig
                return @{ Status = "Updated"; Id = $existingProfile.id }
            }
        }
        else {
            Write-Host "  Creating new driver update profile: $displayName" -ForegroundColor Green

            if ($PSCmdlet.ShouldProcess($displayName, "Create Driver Update Profile")) {
                $createUri = "https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles"
                $response = Invoke-GraphRequestWithRetry -Method POST -Uri $createUri -Body $Configuration
                return @{ Status = "Created"; Id = $response.id }
            }
        }
    }
    catch {
        Write-Error "Failed to deploy driver update profile '$displayName': $_"
        return @{ Status = "Failed"; Error = $_.Exception.Message }
    }

    return @{ Status = "Skipped" }
}

#endregion

#region App Protection Deployment

function Deploy-AppProtectionPolicy {
    <#
    .SYNOPSIS
        Deploys an App Protection Policy (MAM).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration
    )

    $displayName = $Configuration.displayName
    $odataType = $Configuration.'@odata.type'

    # Determine platform and endpoint
    $platform = switch -Regex ($odataType) {
        'ios' { 'ios'; break }
        'android' { 'android'; break }
        default { 'unknown' }
    }

    $endpoint = switch ($platform) {
        'ios' { 'iosManagedAppProtections' }
        'android' { 'androidManagedAppProtections' }
    }

    if (-not $endpoint) {
        Write-Error "Unknown app protection policy type: $odataType"
        return @{ Status = "Failed"; Error = "Unknown policy type" }
    }

    try {
        # Check if policy exists
        $uri = "https://graph.microsoft.com/v1.0/deviceAppManagement/$endpoint"
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri
        $existingPolicy = $response.value | Where-Object { $_.displayName -eq $displayName } | Select-Object -First 1

        if ($existingPolicy) {
            Write-Host "  Updating existing app protection policy: $displayName" -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess($displayName, "Update App Protection Policy")) {
                $updateUri = "https://graph.microsoft.com/v1.0/deviceAppManagement/$endpoint/$($existingPolicy.id)"
                $updateConfig = $Configuration | Select-Object -Property * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, apps

                Invoke-GraphRequestWithRetry -Method PATCH -Uri $updateUri -Body $updateConfig
                return @{ Status = "Updated"; Id = $existingPolicy.id }
            }
        }
        else {
            Write-Host "  Creating new app protection policy: $displayName" -ForegroundColor Green

            if ($PSCmdlet.ShouldProcess($displayName, "Create App Protection Policy")) {
                $createUri = "https://graph.microsoft.com/v1.0/deviceAppManagement/$endpoint"
                $response = Invoke-GraphRequestWithRetry -Method POST -Uri $createUri -Body $Configuration
                return @{ Status = "Created"; Id = $response.id }
            }
        }
    }
    catch {
        Write-Error "Failed to deploy app protection policy '$displayName': $_"
        return @{ Status = "Failed"; Error = $_.Exception.Message }
    }

    return @{ Status = "Skipped" }
}

#endregion

#region Cache Management

function Clear-IdentityCache {
    <#
    .SYNOPSIS
        Clears the identity cache.
    #>
    [CmdletBinding()]
    param()

    $Script:IdentityCache.Groups.Clear()
    $Script:IdentityCache.NamedLocations.Clear()
    Write-Verbose "Identity cache cleared"
}

function Get-IdentityCache {
    <#
    .SYNOPSIS
        Returns the current identity cache.
    #>
    [CmdletBinding()]
    param()

    return $Script:IdentityCache
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'Connect-IntuneGraph',
    'Test-IntuneGraphConnection',
    'Read-ConfigurationFile',
    'Resolve-Placeholders',
    'Deploy-EntraGroup',
    'Deploy-NamedLocation',
    'Deploy-ConditionalAccessPolicy',
    'Deploy-CompliancePolicy',
    'Deploy-WindowsUpdateRing',
    'Deploy-DriverUpdateProfile',
    'Deploy-AppProtectionPolicy',
    'Clear-IdentityCache',
    'Get-IdentityCache'
)
