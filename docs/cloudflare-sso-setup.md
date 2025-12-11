# Cloudflare Zero Trust SSO Setup Guide

## Overview

This guide covers configuring Single Sign-On (SSO) between Microsoft Entra ID (ryanturcotte.com tenant) and Cloudflare Zero Trust Access (fortbox.cloudflareaccess.com).

## Architecture

```
┌─────────────────────────┐         ┌─────────────────────────┐
│   Microsoft Entra ID    │         │  Cloudflare Zero Trust  │
│   (ryanturcotte.com)    │◄───────►│      (fortbox)          │
│                         │  OIDC   │                         │
│  - User Authentication  │         │  - Access Policies      │
│  - Group Membership     │         │  - Application Gateway  │
│  - MFA Enforcement      │         │  - WARP Client          │
└─────────────────────────┘         └─────────────────────────┘
```

## Prerequisites

- Microsoft Entra ID Global Administrator or Application Administrator role
- Cloudflare Zero Trust account with Access enabled
- PowerShell 7.0+ with Microsoft.Graph module

## Quick Start (Automated)

Run the deployment script to automatically configure Entra ID:

```powershell
# Navigate to IAM scripts
cd ALZ-v3/scripts/iam

# Run the SSO deployment
./Deploy-CloudflareSSO.ps1 -CloudflareTeamName "fortbox"
```

The script will:
1. Create the App Registration in Entra ID
2. Configure required API permissions
3. Grant admin consent
4. Generate a client secret
5. Output all values needed for Cloudflare

## Manual Setup

### Step 1: Create Entra ID App Registration

1. Go to [Microsoft Entra Admin Center](https://entra.microsoft.com)
2. Navigate to **Applications** > **App registrations**
3. Click **New registration**
4. Configure:
   - **Name**: `Cloudflare Zero Trust Access`
   - **Supported account types**: Accounts in this organizational directory only
   - **Redirect URI**:
     - Platform: Web
     - URL: `https://fortbox.cloudflareaccess.com/cdn-cgi/access/callback`
5. Click **Register**

### Step 2: Configure API Permissions

1. In the App Registration, go to **API permissions**
2. Click **Add a permission** > **Microsoft Graph** > **Delegated permissions**
3. Add these permissions:
   - `email`
   - `offline_access`
   - `openid`
   - `profile`
   - `User.Read`
   - `Directory.Read.All` (for group sync)
   - `GroupMember.Read.All` (for group sync)
4. Click **Grant admin consent for [tenant]**

### Step 3: Create Client Secret

1. Go to **Certificates & secrets**
2. Click **New client secret**
3. Configure:
   - **Description**: `Cloudflare Zero Trust Secret`
   - **Expires**: 12 months (or your preference)
4. Click **Add**
5. **COPY THE SECRET VALUE NOW** - it will not be shown again!

### Step 4: Collect Configuration Values

From the App Registration **Overview** page, collect:

| Value | Location |
|-------|----------|
| Application (client) ID | Overview page |
| Directory (tenant) ID | Overview page |
| Client Secret | Certificates & secrets (from Step 3) |

### Step 5: Configure Cloudflare Zero Trust

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Settings** > **Authentication**
3. Under **Login methods**, click **Add new**
4. Select **Azure AD**
5. Enter the values from Step 4:
   - **Application ID**: [Your Application ID]
   - **Application Secret**: [Your Client Secret]
   - **Directory ID**: [Your Tenant ID]
6. Configure optional settings:
   - ✅ **Enable PKCE** (recommended for security)
   - ✅ **Support groups** (for group-based policies)
7. Click **Save**
8. Click **Test** to verify the connection

## Configuration Values

### Entra ID App Registration

| Setting | Value |
|---------|-------|
| Application Name | Cloudflare Zero Trust Access |
| Redirect URI | `https://fortbox.cloudflareaccess.com/cdn-cgi/access/callback` |
| Sign-in Audience | Single tenant (ryanturcotte.com only) |

### Required Permissions

| Permission | Type | Purpose |
|------------|------|---------|
| email | Delegated | User email for identification |
| openid | Delegated | OIDC authentication |
| profile | Delegated | User profile information |
| offline_access | Delegated | Refresh tokens |
| User.Read | Delegated | Basic user info |
| Directory.Read.All | Delegated | Group membership (optional) |
| GroupMember.Read.All | Delegated | Group sync (optional) |

## Group-Based Access Policies

To use Entra ID groups in Cloudflare Access policies:

### 1. Enable Group Support in Cloudflare

In the Azure AD identity provider settings:
- Enable **Support groups**

### 2. Get Group Object IDs

In Entra ID:
1. Go to **Groups**
2. Find the group you want to use
3. Copy the **Object ID**

### 3. Create Access Policy

In Cloudflare Zero Trust:
1. Create or edit an Access Application
2. Add a policy rule:
   - **Selector**: Azure Groups
   - **Value**: [Paste the Object ID]

## SCIM Provisioning (Optional)

For automatic user/group sync:

### 1. Enable SCIM in Cloudflare

1. In the Azure AD identity provider settings
2. Enable **SCIM**
3. Copy the **SCIM Endpoint** and **SCIM Secret**

### 2. Configure SCIM in Entra ID

1. Go to **Enterprise applications**
2. Create a new application: **Cloudflare Zero Trust SCIM**
3. Go to **Provisioning**
4. Set mode to **Automatic**
5. Enter:
   - **Tenant URL**: [SCIM Endpoint from Cloudflare]
   - **Secret Token**: [SCIM Secret from Cloudflare]
6. Test connection
7. Configure attribute mappings
8. Turn on provisioning

**Note**: Nested groups are not supported. Groups must have direct membership.

## Testing the Integration

### 1. Test from Cloudflare Dashboard

1. In the identity provider settings, click **Test**
2. Authenticate with your Entra ID credentials
3. Verify successful authentication

### 2. Test Access Application

1. Create a simple Access Application
2. Add a policy allowing your user
3. Access the protected resource
4. Verify SSO redirects to Microsoft login

## Troubleshooting

### "Invalid redirect URI"

**Cause**: Redirect URI mismatch between Entra ID and Cloudflare

**Solution**: Verify the redirect URI is exactly:
```
https://fortbox.cloudflareaccess.com/cdn-cgi/access/callback
```

### "AADSTS50011: Reply URL does not match"

**Cause**: The reply URL in the request doesn't match the app registration

**Solution**:
1. Check the App Registration redirect URIs
2. Ensure no trailing slash
3. Ensure HTTPS (not HTTP)

### "Consent required" errors

**Cause**: Admin consent not granted for API permissions

**Solution**:
1. Go to App Registration > API permissions
2. Click "Grant admin consent for [tenant]"

### Groups not appearing in policies

**Cause**: Group sync not enabled or permissions missing

**Solution**:
1. Verify "Support groups" is enabled in Cloudflare
2. Verify Directory.Read.All and GroupMember.Read.All permissions
3. Verify admin consent is granted

## Security Recommendations

1. **Use PKCE**: Enable Proof Key for Code Exchange in Cloudflare settings
2. **Short-lived secrets**: Use 6-12 month secret expiry and rotate regularly
3. **Least privilege**: Only grant required permissions
4. **Group-based policies**: Use groups instead of individual users
5. **Conditional Access**: Apply Entra ID Conditional Access policies to the app
6. **Monitor sign-ins**: Review Entra ID sign-in logs regularly

## Maintenance

### Secret Rotation

1. Create a new client secret in Entra ID
2. Update the secret in Cloudflare
3. Verify authentication works
4. Delete the old secret

### Annual Review

- Review API permissions (remove unused)
- Review group memberships
- Update documentation
- Test disaster recovery

## References

- [Cloudflare Entra ID Integration](https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/entra-id/)
- [Microsoft Entra + Cloudflare](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/cloudflare-integration)
- [Cloudflare SSO Integration Guide](https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/)
