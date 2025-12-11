#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications

<#
.SYNOPSIS
    Deploys Cloudflare Zero Trust SSO integration to Microsoft Entra ID.

.DESCRIPTION
    Creates and configures the Entra ID App Registration required for Cloudflare
    Zero Trust Access OIDC integration. This script:

    1. Creates the App Registration with correct redirect URI
    2. Configures required API permissions (Microsoft Graph)
    3. Grants admin consent for the permissions
    4. Creates a client secret (valid for 1 year)
    5. Outputs all values needed for Cloudflare configuration

.PARAMETER TenantId
    The Entra ID tenant ID (optional - uses connected tenant if not specified)

.PARAMETER CloudflareTeamName
    Your Cloudflare Zero Trust team name (e.g., 'fortbox')

.PARAMETER SecretValidityDays
    Number of days the client secret is valid (default: 365)

.PARAMETER WhatIf
    Preview changes without making them

.EXAMPLE
    ./Deploy-CloudflareSSO.ps1 -CloudflareTeamName "fortbox"

.EXAMPLE
    ./Deploy-CloudflareSSO.ps1 -CloudflareTeamName "fortbox" -SecretValidityDays 180

.NOTES
    SECURITY: The client secret is displayed only once. Store it securely!

    After running this script, you must:
    1. Go to Cloudflare Zero Trust Dashboard
    2. Navigate to Settings > Authentication > Login methods
    3. Add Azure AD as identity provider
    4. Enter the Application ID, Client Secret, and Directory ID
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$CloudflareTeamName,

    [Parameter()]
    [int]$SecretValidityDays = 365,

    [Parameter()]
    [switch]$EnableGroupSync
)

$ErrorActionPreference = 'Stop'

#region Functions

function Connect-ToGraph {
    $requiredScopes = @(
        "Application.ReadWrite.All",
        "Directory.ReadWrite.All"
    )

    Write-Host "`nConnecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes $requiredScopes -NoWelcome

    $context = Get-MgContext
    if (-not $context) {
        throw "Failed to connect to Microsoft Graph"
    }

    Write-Host "Connected to tenant: $($context.TenantId)" -ForegroundColor Green
    return $context
}

function New-CloudflareAppRegistration {
    param(
        [string]$TeamName,
        [string]$TenantId
    )

    $appName = "Cloudflare Zero Trust Access"
    $callbackUrl = "https://$TeamName.cloudflareaccess.com/cdn-cgi/access/callback"

    Write-Host "`nCreating App Registration: $appName" -ForegroundColor Cyan
    Write-Host "Callback URL: $callbackUrl" -ForegroundColor Gray

    # Check if app already exists
    $existingApp = Get-MgApplication -Filter "displayName eq '$appName'" -ErrorAction SilentlyContinue

    if ($existingApp) {
        Write-Host "App Registration already exists: $($existingApp.AppId)" -ForegroundColor Yellow
        $response = Read-Host "Update existing app? (y/n)"
        if ($response -ne 'y') {
            return $existingApp
        }
    }

    # Define required permissions (Microsoft Graph)
    $requiredResourceAccess = @{
        ResourceAppId = "00000003-0000-0000-c000-000000000000"  # Microsoft Graph
        ResourceAccess = @(
            @{ Id = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; Type = "Scope" }  # email
            @{ Id = "7427e0e9-2fba-42fe-b0c0-848c9e6a8182"; Type = "Scope" }  # offline_access
            @{ Id = "37f7f235-527c-4136-accd-4a02d197296e"; Type = "Scope" }  # openid
            @{ Id = "14dad69e-099b-42c9-810b-d002981feec1"; Type = "Scope" }  # profile
            @{ Id = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; Type = "Scope" }  # User.Read
            @{ Id = "06da0dbc-49e2-44d2-8312-53f166ab848a"; Type = "Scope" }  # Directory.Read.All
            @{ Id = "bc024368-1153-4739-b217-4326f2e966d0"; Type = "Scope" }  # GroupMember.Read.All
        )
    }

    # Create app registration body
    $appBody = @{
        DisplayName = $appName
        Description = "OIDC integration for Cloudflare Zero Trust Access - enables SSO authentication for protected applications via $TeamName.cloudflareaccess.com"
        SignInAudience = "AzureADMyOrg"
        Web = @{
            RedirectUris = @($callbackUrl)
            ImplicitGrantSettings = @{
                EnableAccessTokenIssuance = $false
                EnableIdTokenIssuance = $true
            }
        }
        RequiredResourceAccess = @($requiredResourceAccess)
        OptionalClaims = @{
            IdToken = @(
                @{ Name = "email"; Essential = $true }
                @{ Name = "upn"; Essential = $false }
                @{ Name = "groups"; Essential = $false }
            )
            AccessToken = @(
                @{ Name = "email"; Essential = $true }
            )
        }
    }

    if ($existingApp) {
        # Update existing app
        Update-MgApplication -ApplicationId $existingApp.Id -BodyParameter $appBody
        $app = Get-MgApplication -ApplicationId $existingApp.Id
    }
    else {
        # Create new app
        $app = New-MgApplication -BodyParameter $appBody
    }

    Write-Host "App Registration created/updated: $($app.AppId)" -ForegroundColor Green
    return $app
}

function New-AppClientSecret {
    param(
        [string]$AppId,
        [int]$ValidityDays
    )

    Write-Host "`nCreating client secret (valid for $ValidityDays days)..." -ForegroundColor Cyan

    $endDate = (Get-Date).AddDays($ValidityDays)

    $secretBody = @{
        PasswordCredential = @{
            DisplayName = "Cloudflare Zero Trust Secret"
            EndDateTime = $endDate
        }
    }

    $secret = Add-MgApplicationPassword -ApplicationId $AppId -BodyParameter $secretBody

    Write-Host "Client secret created (expires: $endDate)" -ForegroundColor Green
    return $secret.SecretText
}

function Grant-AdminConsent {
    param(
        [string]$AppId,
        [string]$TenantId
    )

    Write-Host "`nGranting admin consent for API permissions..." -ForegroundColor Cyan

    # Get the service principal
    $sp = Get-MgServicePrincipal -Filter "appId eq '$AppId'" -ErrorAction SilentlyContinue

    if (-not $sp) {
        # Create service principal
        $sp = New-MgServicePrincipal -AppId $AppId
        Write-Host "Service Principal created" -ForegroundColor Green
    }

    # Get Microsoft Graph service principal
    $graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

    # Grant OAuth2 permissions
    $delegatedPermissions = @(
        "e1fe6dd8-ba31-4d61-89e7-88639da4683d"  # email / User.Read
        "7427e0e9-2fba-42fe-b0c0-848c9e6a8182"  # offline_access
        "37f7f235-527c-4136-accd-4a02d197296e"  # openid
        "14dad69e-099b-42c9-810b-d002981feec1"  # profile
        "06da0dbc-49e2-44d2-8312-53f166ab848a"  # Directory.Read.All
        "bc024368-1153-4739-b217-4326f2e966d0"  # GroupMember.Read.All
    )

    $grantBody = @{
        ClientId = $sp.Id
        ConsentType = "AllPrincipals"
        ResourceId = $graphSp.Id
        Scope = "email offline_access openid profile User.Read Directory.Read.All GroupMember.Read.All"
    }

    try {
        New-MgOauth2PermissionGrant -BodyParameter $grantBody -ErrorAction SilentlyContinue
        Write-Host "Admin consent granted" -ForegroundColor Green
    }
    catch {
        Write-Warning "Could not grant admin consent automatically. Please grant consent in Azure Portal."
    }
}

function Write-ConfigurationOutput {
    param(
        [object]$App,
        [string]$ClientSecret,
        [string]$TenantId,
        [string]$TeamName
    )

    $output = @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                    CLOUDFLARE ZERO TRUST CONFIGURATION                       ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  Use these values in Cloudflare Zero Trust Dashboard:                        ║
║  Settings > Authentication > Login methods > Add new > Azure AD              ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────┐
│ ENTRA ID VALUES (copy these to Cloudflare)                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ Application (Client) ID:                                                    │
│ $($App.AppId)
│                                                                             │
│ Directory (Tenant) ID:                                                      │
│ $TenantId
│                                                                             │
│ Client Secret:                                                              │
│ $ClientSecret
│                                                                             │
│ ⚠️  SAVE THE CLIENT SECRET NOW - IT WILL NOT BE SHOWN AGAIN!               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ CLOUDFLARE SETTINGS                                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ Cloudflare Team:     $TeamName
│ Callback URL:        https://$TeamName.cloudflareaccess.com/cdn-cgi/access/callback
│                                                                             │
│ Recommended Optional Settings:                                              │
│ ✓ Enable PKCE                                                               │
│ ✓ Support groups (for group-based Access policies)                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ NEXT STEPS                                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ 1. Log into Cloudflare Zero Trust Dashboard                                 │
│    https://one.dash.cloudflare.com/                                         │
│                                                                             │
│ 2. Go to Settings > Authentication > Login methods                          │
│                                                                             │
│ 3. Click "Add new" and select "Azure AD"                                    │
│                                                                             │
│ 4. Enter the Application ID, Client Secret, and Directory ID above          │
│                                                                             │
│ 5. Enable "Support groups" if you want group-based policies                 │
│                                                                             │
│ 6. Click "Save" and test the connection                                     │
│                                                                             │
│ 7. Create Access Applications to protect your resources                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

"@

    Write-Host $output -ForegroundColor White

    # Save to file
    $outputFile = Join-Path $PSScriptRoot "cloudflare-sso-config-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    $output | Out-File -FilePath $outputFile -Encoding UTF8
    Write-Host "Configuration saved to: $outputFile" -ForegroundColor Cyan
    Write-Host "⚠️  Delete this file after configuring Cloudflare!" -ForegroundColor Yellow
}

#endregion

#region Main Execution

Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║           CLOUDFLARE ZERO TRUST SSO DEPLOYMENT                              ║
║                                                                              ║
║  This script configures Microsoft Entra ID for Cloudflare Zero Trust        ║
║  Access OIDC integration.                                                    ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

if ($WhatIfPreference) {
    Write-Host "[WHAT-IF MODE] No changes will be made`n" -ForegroundColor Yellow
}

# Connect to Graph
$context = Connect-ToGraph

if (-not $TenantId) {
    $TenantId = $context.TenantId
}

Write-Host "`nConfiguration:" -ForegroundColor Cyan
Write-Host "  Tenant ID: $TenantId" -ForegroundColor White
Write-Host "  Cloudflare Team: $CloudflareTeamName" -ForegroundColor White
Write-Host "  Secret Validity: $SecretValidityDays days" -ForegroundColor White

if ($PSCmdlet.ShouldProcess("Entra ID", "Create Cloudflare Zero Trust App Registration")) {

    # Create/Update App Registration
    $app = New-CloudflareAppRegistration -TeamName $CloudflareTeamName -TenantId $TenantId

    # Create client secret
    $clientSecret = New-AppClientSecret -AppId $app.Id -ValidityDays $SecretValidityDays

    # Grant admin consent
    Grant-AdminConsent -AppId $app.AppId -TenantId $TenantId

    # Output configuration
    Write-ConfigurationOutput -App $app -ClientSecret $clientSecret -TenantId $TenantId -TeamName $CloudflareTeamName

    Write-Host "`n✅ Entra ID configuration complete!" -ForegroundColor Green
    Write-Host "Now configure Cloudflare using the values above.`n" -ForegroundColor White
}

#endregion
