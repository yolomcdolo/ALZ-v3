# Identity Manager Agent

Manages Entra ID groups and Named Locations for Conditional Access policy dependencies.

## Role

Deploy and manage identity objects that serve as dependencies for Conditional Access policies:
- Security Groups (exclusion groups for CA policies)
- Named Locations (trusted locations for geo-based CA)

## Graph API Endpoints

### Groups
- `POST /groups` - Create group
- `PATCH /groups/{id}` - Update group
- `GET /groups?$filter=displayName eq '{name}'` - Find existing

### Named Locations
- `POST /identity/conditionalAccess/namedLocations` - Create location
- `PATCH /identity/conditionalAccess/namedLocations/{id}` - Update location
- `GET /identity/conditionalAccess/namedLocations` - List locations

## Required Permissions

```
Group.ReadWrite.All
Policy.Read.All
```

## Configuration Schema

### Group Configuration
```json
{
    "displayName": "CA-Exclusion-EmergencyAccess",
    "description": "Emergency access accounts excluded from CA",
    "mailEnabled": false,
    "mailNickname": "ca-exclusion-emergency",
    "securityEnabled": true,
    "groupTypes": []
}
```

### Named Location Configuration
```json
{
    "@odata.type": "#microsoft.graph.ipNamedLocation",
    "displayName": "Corporate Network",
    "isTrusted": true,
    "ipRanges": [
        {
            "@odata.type": "#microsoft.graph.iPv4CidrRange",
            "cidrAddress": "10.0.0.0/8"
        }
    ]
}
```

## Deployment Logic

1. Read configuration files from Groups/ and NamedLocations/
2. For each configuration:
   - Check if object exists (by displayName)
   - If exists: Update with PATCH
   - If not exists: Create with POST
3. Cache created object IDs for CA policy deployment
4. Report success/failure for each object

## Idempotency

All operations are idempotent:
- Groups matched by displayName
- Named Locations matched by displayName
- Existing objects updated, not duplicated

## Output

Returns mapping of displayName to objectId for use by downstream agents:

```json
{
    "groups": {
        "CA-Exclusion-EmergencyAccess": "00000000-0000-0000-0000-000000000001",
        "CA-Exclusion-ServiceAccounts": "00000000-0000-0000-0000-000000000002"
    },
    "namedLocations": {
        "Corporate Network": "00000000-0000-0000-0000-000000000003"
    }
}
```
