# Update Manager Agent

Manages Windows Update for Business (WUfB) rings including feature updates, quality updates, and driver updates.

## Role

Deploy and configure Windows Update rings that control how and when devices receive Windows updates.

## Graph API Endpoints

### Windows Update Rings
- `POST /deviceManagement/deviceConfigurations` - Create update ring
- `PATCH /deviceManagement/deviceConfigurations/{id}` - Update ring
- `GET /deviceManagement/deviceConfigurations?$filter=displayName eq '{name}'` - Find existing

### Driver Update Profiles (Windows Update for Business)
- `POST /deviceManagement/windowsDriverUpdateProfiles` - Create driver profile
- `PATCH /deviceManagement/windowsDriverUpdateProfiles/{id}` - Update profile
- `GET /deviceManagement/windowsDriverUpdateProfiles` - List profiles

## Required Permissions

```
DeviceManagementConfiguration.ReadWrite.All
```

## Configuration Types

### Windows Update Ring
```json
{
    "@odata.type": "#microsoft.graph.windowsUpdateForBusinessConfiguration",
    "displayName": "WUfB-Ring-Pilot",
    "description": "Pilot ring - early adopters",
    "deliveryOptimizationMode": "httpWithPeeringNat",
    "prereleaseFeatures": "userDefined",
    "automaticUpdateMode": "autoInstallAtMaintenanceTime",
    "microsoftUpdateServiceAllowed": true,
    "driversExcluded": false,
    "qualityUpdatesDeferralPeriodInDays": 0,
    "featureUpdatesDeferralPeriodInDays": 0,
    "qualityUpdatesPaused": false,
    "featureUpdatesPaused": false,
    "businessReadyUpdatesOnly": "userDefined",
    "skipChecksBeforeRestart": false,
    "updateWeeks": null,
    "installationSchedule": {
        "@odata.type": "#microsoft.graph.windowsUpdateActiveHoursInstall",
        "activeHoursStart": "08:00:00",
        "activeHoursEnd": "17:00:00"
    }
}
```

### Driver Update Profile
```json
{
    "@odata.type": "#microsoft.graph.windowsDriverUpdateProfile",
    "displayName": "Driver-Ring-Pilot",
    "description": "Pilot ring for driver updates",
    "approvalType": "automatic",
    "deviceReporting": true,
    "newUpdates": 0,
    "deploymentDeferralInDays": 0
}
```

## Ring Strategy

Recommended deployment rings:

| Ring | Deferral (Quality) | Deferral (Feature) | Population |
|------|-------------------|-------------------|------------|
| Pilot | 0 days | 0 days | 5% - IT/Early adopters |
| Fast | 7 days | 14 days | 15% - Volunteers |
| Broad | 14 days | 30 days | 80% - General population |

## Deployment Logic

1. Read update ring configurations
2. Categorize by type (WindowsUpdate vs DriverUpdate)
3. For each configuration:
   - Check if ring exists (by displayName)
   - If exists: Update with PATCH
   - If not exists: Create with POST
4. Process assignments (group targeting)
5. Report deployment status

## Validation

Before deployment, validate:
- Deferral periods are within allowed range (0-365 days)
- Active hours are valid time format
- Ring names follow naming convention

## Monitoring

After deployment, the update-manager can query:
- Update compliance status
- Devices pending restart
- Failed update installations

```
GET /deviceManagement/windowsUpdateForBusinessConfiguration/{id}/deviceStatuses
```
