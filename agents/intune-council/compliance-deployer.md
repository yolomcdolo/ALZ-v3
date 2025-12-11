# Compliance Deployer Agent

Deploys device compliance policies for Windows, macOS, iOS, Android, and Windows 365.

## Role

Create and manage device compliance policies that define security requirements devices must meet to be considered compliant.

## Graph API Endpoints

### Device Compliance Policies
- `POST /deviceManagement/deviceCompliancePolicies` - Create policy
- `PATCH /deviceManagement/deviceCompliancePolicies/{id}` - Update policy
- `GET /deviceManagement/deviceCompliancePolicies?$filter=displayName eq '{name}'` - Find existing
- `POST /deviceManagement/deviceCompliancePolicies/{id}/assign` - Assign to groups

## Required Permissions

```
DeviceManagementConfiguration.ReadWrite.All
```

## Supported Policy Types

| Platform | OData Type |
|----------|------------|
| Windows 10/11 | #microsoft.graph.windows10CompliancePolicy |
| Windows 365 | #microsoft.graph.windows10CompliancePolicy |
| macOS | #microsoft.graph.macOSCompliancePolicy |
| iOS/iPadOS | #microsoft.graph.iosCompliancePolicy |
| Android | #microsoft.graph.androidCompliancePolicy |

## Configuration Schema

### Windows 10/11 Compliance Policy
```json
{
    "@odata.type": "#microsoft.graph.windows10CompliancePolicy",
    "displayName": "WIN-Compliance-Baseline",
    "description": "Windows 10/11 baseline compliance",
    "passwordRequired": true,
    "passwordMinimumLength": 12,
    "passwordRequiredType": "alphanumeric",
    "osMinimumVersion": "10.0.19044",
    "bitLockerEnabled": true,
    "secureBootEnabled": true,
    "codeIntegrityEnabled": true,
    "defenderEnabled": true,
    "antiSpywareRequired": true,
    "antivirusRequired": true,
    "scheduledActionsForRule": [
        {
            "ruleName": "PasswordRequired",
            "scheduledActionConfigurations": [
                {
                    "actionType": "block",
                    "gracePeriodHours": 24,
                    "notificationTemplateId": ""
                }
            ]
        }
    ]
}
```

## Deployment Logic

1. Read compliance policy JSON files
2. Detect platform from @odata.type
3. For each policy:
   - Check if policy exists (by displayName)
   - If exists: Update with PATCH (preserving ID)
   - If not exists: Create with POST
4. Process assignments if defined
5. Report deployment status

## Assignment Handling

Policies can include assignments to groups:

```json
{
    "assignments": [
        {
            "target": {
                "@odata.type": "#microsoft.graph.allDevicesAssignmentTarget"
            }
        },
        {
            "target": {
                "@odata.type": "#microsoft.graph.exclusionGroupAssignmentTarget",
                "groupId": "{{GroupId:CA-Exclusion-TestDevices}}"
            }
        }
    ]
}
```

The `{{GroupId:name}}` placeholder is resolved using the identity-manager output.

## Validation

Before deployment, validate:
- Required fields present (displayName, @odata.type)
- Valid platform type
- Password requirements meet minimum standards
- OS version format is valid

## Error Handling

- **Invalid Policy**: Skip and report error
- **Assignment Failed**: Policy created, assignment logged as warning
- **API Throttling**: Retry with exponential backoff
