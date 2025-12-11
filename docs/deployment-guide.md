# Deployment Guide

## Overview

This guide covers deploying Azure Landing Zone hub-spoke architecture using ALZ-v3.

## Deployment Methods

### 1. GitHub Actions (Recommended for Production)

Navigate to **Actions** → **Deploy Hub-Spoke Infrastructure** → **Run workflow**

Configure:
- Environment: `prod` / `staging` / `dev`
- Location: `eastus` (default)
- VPN Gateway: `false` (skip for faster deployment)
- Bastion: `true` (for secure VM access)
- Spoke count: `2-5`
- VM counts per spoke

### 2. Local Deployment

```bash
# Clone repository
git clone https://github.com/yolomcdolo/ALZ-v3.git
cd ALZ-v3

# Run deployment script
./scripts/deploy-local.sh prod eastus 2 false true 3 2
```

Parameters:
1. Environment (prod/staging/dev)
2. Location (eastus/westus2/etc)
3. Spoke count
4. Deploy VPN Gateway (true/false)
5. Deploy Bastion (true/false)
6. VM count in Spoke1
7. VM count in Spoke2

### 3. Azure Council (/azure command)

Using Claude Code:
```
/azure Deploy a hub-spoke network with 2 spoke VNets, Azure Firewall, Azure Bastion, 3 Ubuntu VMs in spoke1, 2 Windows VMs in spoke2
```

## Prerequisites

### Azure CLI
```bash
az login
az account set --subscription "Your-Subscription-Name"
```

### GitHub Actions Secrets
- `AZURE_CREDENTIALS` - Service principal JSON
- `AZURE_SUBSCRIPTION_ID` - Target subscription
- `VM_ADMIN_PASSWORD` - VM administrator password

### Create Service Principal
```bash
az ad sp create-for-rbac --name "sp-alz-v3-github" \
  --role contributor \
  --scopes /subscriptions/{subscription-id} \
  --sdk-auth
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Hub VNet (10.0.0.0/16)                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Firewall   │  │   Bastion    │  │  Management  │      │
│  │  10.0.1.0/26 │  │  10.0.2.0/26 │  │  10.0.3.0/24 │      │
│  │   (10.0.1.4) │  │              │  │              │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
          │                                    │
          │ VNet Peering                       │ VNet Peering
          ▼                                    ▼
┌─────────────────────┐              ┌─────────────────────┐
│ Spoke1 (10.1.0.0/16)│              │ Spoke2 (10.2.0.0/16)│
│  ┌───────────────┐  │              │  ┌───────────────┐  │
│  │   Workloads   │  │◄────────────►│  │   Workloads   │  │
│  │  10.1.1.0/24  │  │  via Firewall │  │  10.2.1.0/24  │  │
│  │  Ubuntu VMs   │  │              │  │  Windows VMs  │  │
│  └───────────────┘  │              │  └───────────────┘  │
└─────────────────────┘              └─────────────────────┘
```

## Deployment Phases

1. **Pre-Flight Checks**
   - Shell detection (Git Bash needs PowerShell wrapper)
   - Azure provider registration
   - VM quota validation

2. **Foundation**
   - Resource groups (parallel)
   - Log Analytics workspace

3. **Hub Network**
   - Hub VNet creation
   - Subnets (sequential - same VNet requirement)

4. **Hub Services**
   - Azure Firewall (with IP configuration)
   - Azure Bastion (parallel with --no-wait)

5. **Spoke Networks**
   - Spoke VNets (parallel)
   - Workload subnets

6. **Connectivity**
   - VNet peering (bidirectional)
   - NSGs with hub-spoke rules
   - Route tables with firewall routes
   - Firewall network rules

7. **Compute**
   - VMs deployment (parallel with --no-wait)
   - Wait for provisioning

8. **Validation**
   - Connectivity test spoke-to-spoke
   - Documentation generation

## Estimated Costs

| Resource | Monthly Cost |
|----------|-------------|
| Azure Firewall Standard | ~$750 |
| Azure Bastion Basic | ~$140 |
| VPN Gateway (optional) | ~$140 |
| 3x Ubuntu B2s VMs | ~$60 |
| 2x Windows D2s_v3 VMs | ~$200 |
| Log Analytics | ~$10-50 |
| Storage | ~$20-40 |
| **Total (without VPN)** | **~$1,200-1,300** |

## Cleanup

### GitHub Actions
Run **Destroy Infrastructure** workflow with confirmation "DESTROY"

### Local
```bash
./scripts/destroy-local.sh prod eastus
```

### Manual
```bash
az group delete -n rg-prod-network-hub-eastus --yes --no-wait
az group delete -n rg-prod-network-spoke1-eastus --yes --no-wait
az group delete -n rg-prod-network-spoke2-eastus --yes --no-wait
```

## Troubleshooting

### Subnet Creation Fails
Error: `AnotherOperationInProgress`
Solution: Subnets on same VNet must be created sequentially, not in parallel.

### Storage Account Name Taken
Error: `StorageAccountAlreadyTaken`
Solution: Use unique suffix (timestamp) for storage account names.

### Git Bash Path Translation
Error: Resource IDs like `/subscriptions/...` become `C:/Program Files/Git/subscriptions/...`
Solution: Use PowerShell wrapper for commands with resource IDs.

### Firewall IP Configuration Null
Issue: Firewall created with --no-wait has null privateIPAddress
Solution: Wait for firewall or explicitly create IP configuration.
