# App Protection Agent

Deploys Mobile Application Management (MAM) policies for BYOD and managed device scenarios.

## Role

Create and manage App Protection Policies that secure corporate data within mobile applications on iOS and Android devices.

## Graph API Endpoints

### iOS App Protection Policies
- `POST /deviceAppManagement/iosManagedAppProtections` - Create policy
- `PATCH /deviceAppManagement/iosManagedAppProtections/{id}` - Update policy
- `GET /deviceAppManagement/iosManagedAppProtections?$filter=displayName eq '{name}'` - Find existing
- `POST /deviceAppManagement/iosManagedAppProtections/{id}/assign` - Assign to groups

### Android App Protection Policies
- `POST /deviceAppManagement/androidManagedAppProtections` - Create policy
- `PATCH /deviceAppManagement/androidManagedAppProtections/{id}` - Update policy
- `GET /deviceAppManagement/androidManagedAppProtections?$filter=displayName eq '{name}'` - Find existing

## Required Permissions

```
DeviceManagementApps.ReadWrite.All
```

## Policy Types

| Type | Use Case |
|------|----------|
| iosManagedAppProtection | iOS/iPadOS BYOD and managed devices |
| androidManagedAppProtection | Android BYOD and managed devices |
| mdmWindowsInformationProtectionPolicy | Windows Information Protection |

## Configuration Schema

### iOS App Protection Policy
```json
{
    "@odata.type": "#microsoft.graph.iosManagedAppProtection",
    "displayName": "iOS-MAM-Corporate",
    "description": "Corporate data protection for iOS",
    "periodOfflineBeforeAccessCheck": "PT12H",
    "periodOnlineBeforeAccessCheck": "PT30M",
    "allowedInboundDataTransferSources": "managedApps",
    "allowedOutboundDataTransferDestinations": "managedApps",
    "organizationalCredentialsRequired": false,
    "allowedOutboundClipboardSharingLevel": "managedAppsWithPasteIn",
    "dataBackupBlocked": true,
    "deviceComplianceRequired": false,
    "managedBrowserToOpenLinksRequired": true,
    "saveAsBlocked": true,
    "periodOfflineBeforeWipeIsEnforced": "P90D",
    "pinRequired": true,
    "maximumPinRetries": 5,
    "simplePinBlocked": true,
    "minimumPinLength": 6,
    "pinCharacterSet": "numeric",
    "periodBeforePinReset": "PT0S",
    "allowedDataStorageLocations": ["oneDriveForBusiness", "sharePoint"],
    "contactSyncBlocked": false,
    "printBlocked": true,
    "fingerprintBlocked": false,
    "disableAppPinIfDevicePinIsSet": true,
    "apps": [
        {
            "mobileAppIdentifier": {
                "@odata.type": "#microsoft.graph.iosMobileAppIdentifier",
                "bundleId": "com.microsoft.Office.Outlook"
            }
        },
        {
            "mobileAppIdentifier": {
                "@odata.type": "#microsoft.graph.iosMobileAppIdentifier",
                "bundleId": "com.microsoft.teams"
            }
        }
    ]
}
```

### Android App Protection Policy
```json
{
    "@odata.type": "#microsoft.graph.androidManagedAppProtection",
    "displayName": "Android-MAM-Corporate",
    "description": "Corporate data protection for Android",
    "periodOfflineBeforeAccessCheck": "PT12H",
    "periodOnlineBeforeAccessCheck": "PT30M",
    "allowedInboundDataTransferSources": "managedApps",
    "allowedOutboundDataTransferDestinations": "managedApps",
    "allowedOutboundClipboardSharingLevel": "managedAppsWithPasteIn",
    "dataBackupBlocked": true,
    "deviceComplianceRequired": false,
    "managedBrowserToOpenLinksRequired": true,
    "saveAsBlocked": true,
    "periodOfflineBeforeWipeIsEnforced": "P90D",
    "pinRequired": true,
    "maximumPinRetries": 5,
    "simplePinBlocked": true,
    "minimumPinLength": 6,
    "screenCaptureBlocked": true,
    "disableAppEncryptionIfDeviceEncryptionIsEnabled": false,
    "encryptAppData": true,
    "deployedAppCount": 2,
    "minimumRequiredOsVersion": "8.0",
    "minimumRequiredAppVersion": null,
    "apps": [
        {
            "mobileAppIdentifier": {
                "@odata.type": "#microsoft.graph.androidMobileAppIdentifier",
                "packageId": "com.microsoft.office.outlook"
            }
        }
    ]
}
```

## Deployment Logic

1. Read app protection policy JSON files from BYOD/ directory
2. Detect platform from @odata.type (ios vs android)
3. For each policy:
   - Check if policy exists (by displayName)
   - If exists: Update with PATCH
   - If not exists: Create with POST
   - Update app list if specified
4. Process assignments if defined
5. Report deployment status

## App Targeting

Protected apps can be specified in two ways:

1. **Inline in policy**: Include `apps` array in policy JSON
2. **Separate assignment**: Use targetedManagedAppConfigurations endpoint

## BYOD vs Managed Device

| Scenario | Device Enrollment | MAM Enrollment | Data Protection |
|----------|------------------|----------------|-----------------|
| BYOD | No | Yes (app-level) | MAM policy |
| Corporate | Yes (MDM) | Automatic | MDM + MAM |

## Validation

Before deployment, validate:
- Required fields present (displayName, @odata.type)
- Time periods are valid ISO 8601 duration format
- PIN length meets minimum requirements (4+)
- App bundle IDs are valid format
