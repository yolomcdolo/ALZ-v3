# Service Principal Manager Agent

Manages App Registrations and Service Principals with secure credential management, least-privilege permissions, and certificate-based authentication.

## Role

Create and manage workload identities (Service Principals) for automation scenarios with emphasis on:
- Certificate-based authentication (preferred over client secrets)
- Credential storage in Azure Key Vault
- Least-privilege permission grants
- Credential expiration monitoring
- Workload Identity with Managed Identities where possible

## Graph API Endpoints

### App Registrations
- `POST /applications` - Create app registration
- `PATCH /applications/{id}` - Update app registration
- `GET /applications?$filter=displayName eq '{name}'` - Find app
- `POST /applications/{id}/addPassword` - Add client secret (avoid if possible)
- `POST /applications/{id}/addKey` - Add certificate credential (preferred)
- `DELETE /applications/{id}` - Delete app registration

### Service Principals
- `POST /servicePrincipals` - Create service principal
- `PATCH /servicePrincipals/{id}` - Update service principal
- `GET /servicePrincipals/{id}` - Get service principal
- `DELETE /servicePrincipals/{id}` - Delete service principal

### Permissions
- `POST /servicePrincipals/{id}/appRoleAssignments` - Grant application permissions
- `POST /oauth2PermissionGrants` - Grant delegated permissions

## Required Permissions

```
Application.ReadWrite.All
Directory.ReadWrite.All
AppRoleAssignment.ReadWrite.All
```

## Configuration Schema

### Service Principal with Certificate Authentication (Preferred)
```json
{
  "displayName": "sp-automation-prod",
  "description": "Production automation service principal for CI/CD",
  "signInAudience": "AzureADMyOrg",
  "requiredResourceAccess": [
    {
      "resourceAppId": "00000003-0000-0000-c000-000000000000",
      "resourceAccess": [
        {
          "id": "1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9",
          "type": "Role"
        }
      ]
    }
  ],
  "credentialConfiguration": {
    "type": "Certificate",
    "keyVaultName": "kv-iam-prod",
    "certificateName": "sp-automation-prod-cert",
    "expirationDays": 365,
    "autoRotate": true
  },
  "securitySettings": {
    "conditionalAccess": {
      "enableWorkloadIdentityPolicy": true,
      "allowedLocations": ["{{NamedLocationId:Corporate-Network}}"]
    },
    "monitoring": {
      "alertOnCredentialExpiration": 30,
      "alertOnUnusualActivity": true
    }
  }
}
```

### Client Secret Configuration (Discouraged)
```json
{
  "displayName": "sp-legacy-integration",
  "description": "Legacy system integration (migrate to certificate)",
  "credentialConfiguration": {
    "type": "ClientSecret",
    "keyVaultName": "kv-iam-prod",
    "secretName": "sp-legacy-secret",
    "expirationDays": 90,
    "rotationWarningDays": 30
  },
  "migrationPlan": {
    "targetDate": "2026-03-31",
    "migrateToManagedIdentity": true
  }
}
```

## Deployment Logic

```powershell
function Deploy-ServicePrincipal {
    param(
        [Parameter(Mandatory)]
        [object]$Configuration,

        [switch]$WhatIf
    )

    try {
        # 1. Check if app registration exists
        $existingApp = Get-MgApplication -Filter "displayName eq '$($Configuration.displayName)'"

        if ($existingApp) {
            Write-Host "  App exists: $($Configuration.displayName)" -ForegroundColor Yellow
            $appId = $existingApp.Id
        }
        else {
            if ($WhatIf) {
                Write-Host "  [WHAT-IF] Would create app: $($Configuration.displayName)" -ForegroundColor Cyan
                return @{ Status = "Skipped" }
            }

            # Create app registration
            $appParams = @{
                DisplayName = $Configuration.displayName
                Description = $Configuration.description
                SignInAudience = $Configuration.signInAudience
                RequiredResourceAccess = $Configuration.requiredResourceAccess
            }

            $newApp = New-MgApplication -BodyParameter $appParams
            $appId = $newApp.Id

            Write-Host "  Created app: $($Configuration.displayName)" -ForegroundColor Green
        }

        # 2. Create/update service principal
        $existingSp = Get-MgServicePrincipal -Filter "appId eq '$($existingApp.AppId)'"

        if (-not $existingSp -and -not $WhatIf) {
            $sp = New-MgServicePrincipal -AppId $existingApp.AppId
            Write-Host "  Created service principal: $($sp.Id)" -ForegroundColor Green
        }

        # 3. Configure credentials
        if (-not $WhatIf) {
            if ($Configuration.credentialConfiguration.type -eq "Certificate") {
                Add-ServicePrincipalCertificate -AppId $appId -Config $Configuration.credentialConfiguration
            }
            else {
                Add-ServicePrincipalSecret -AppId $appId -Config $Configuration.credentialConfiguration
            }
        }

        # 4. Grant permissions (requires admin consent)
        if (-not $WhatIf) {
            Grant-ServicePrincipalPermissions -ServicePrincipalId $existingSp.Id -Permissions $Configuration.requiredResourceAccess
        }

        return @{
            Status = if ($existingApp) { "Updated" } else { "Created" }
            AppId = $existingApp.AppId
            ObjectId = $appId
            DisplayName = $Configuration.displayName
        }
    }
    catch {
        Write-Error "Failed to deploy service principal: $_"
        return @{ Status = "Failed"; Error = $_.Exception.Message }
    }
}
```

## Security Features

### 1. Certificate-Based Authentication (Preferred)

```powershell
function Add-ServicePrincipalCertificate {
    param(
        [string]$AppId,
        [object]$Config
    )

    # Generate self-signed certificate or use existing from Key Vault
    $cert = Get-AzKeyVaultCertificate -VaultName $Config.keyVaultName -Name $Config.certificateName

    if (-not $cert) {
        # Create new certificate in Key Vault
        $policy = New-AzKeyVaultCertificatePolicy -SubjectName "CN=$($Config.certificateName)" `
            -ValidityInMonths 12 -KeyType RSA -KeySize 2048

        $cert = Add-AzKeyVaultCertificate -VaultName $Config.keyVaultName `
            -Name $Config.certificateName -CertificatePolicy $policy
    }

    # Add certificate to app registration
    $certData = [System.Convert]::ToBase64String($cert.Certificate.GetRawCertData())

    Add-MgApplicationKey -ApplicationId $AppId -KeyCredential @{
        Type = "AsymmetricX509Cert"
        Usage = "Verify"
        Key = [System.Text.Encoding]::UTF8.GetBytes($certData)
    }

    Write-Host "  Added certificate credential (expires: $($cert.Certificate.NotAfter))" -ForegroundColor Green
}
```

### 2. Conditional Access for Workload Identities

```powershell
function Enable-WorkloadIdentityConditionalAccess {
    param(
        [string]$ServicePrincipalId,
        [array]$AllowedLocations
    )

    # Create CA policy for workload identity
    $caPolicy = @{
        displayName = "CA-WorkloadIdentity-$ServicePrincipalId"
        state = "enabledForReportingButNotEnforced"
        conditions = @{
            servicePrincipalRiskLevels = @("medium", "high")
            applications = @{
                includeApplications = @($ServicePrincipalId)
            }
            locations = @{
                includeLocations = @("All")
                excludeLocations = $AllowedLocations
            }
        }
        grantControls = @{
            operator = "OR"
            builtInControls = @("block")
        }
    }

    New-MgIdentityConditionalAccessPolicy -BodyParameter $caPolicy
}
```

### 3. Credential Expiration Monitoring

```powershell
function Monitor-ServicePrincipalCredentials {
    param([int]$WarningThresholdDays = 30)

    $allApps = Get-MgApplication -All

    $expiringCredentials = @()

    foreach ($app in $allApps) {
        # Check password credentials (client secrets)
        foreach ($cred in $app.PasswordCredentials) {
            $daysUntilExpiration = ($cred.EndDateTime - (Get-Date)).Days

            if ($daysUntilExpiration -le $WarningThresholdDays) {
                $expiringCredentials += @{
                    AppName = $app.DisplayName
                    AppId = $app.AppId
                    CredentialType = "ClientSecret"
                    ExpiresOn = $cred.EndDateTime
                    DaysRemaining = $daysUntilExpiration
                }
            }
        }

        # Check certificate credentials
        foreach ($cred in $app.KeyCredentials) {
            $daysUntilExpiration = ($cred.EndDateTime - (Get-Date)).Days

            if ($daysUntilExpiration -le $WarningThresholdDays) {
                $expiringCredentials += @{
                    AppName = $app.DisplayName
                    AppId = $app.AppId
                    CredentialType = "Certificate"
                    ExpiresOn = $cred.EndDateTime
                    DaysRemaining = $daysUntilExpiration
                }
            }
        }
    }

    # Send alerts for expiring credentials
    if ($expiringCredentials.Count -gt 0) {
        Send-ServicePrincipalExpirationAlert -Credentials $expiringCredentials
    }

    return $expiringCredentials
}
```

## Best Practices

1. **Prefer Managed Identities** over Service Principals
2. **Use Certificate Authentication** over client secrets
3. **Store credentials in Azure Key Vault** (never in code/config)
4. **Grant least-privilege permissions** only
5. **Enable Conditional Access for Workload Identities**
6. **Monitor credential expiration** (30-day warning)
7. **Rotate credentials annually** (certificates) or quarterly (secrets)
8. **Disable unused service principals**
9. **Audit service principal activity** regularly
10. **Document service principal purpose** and owner
