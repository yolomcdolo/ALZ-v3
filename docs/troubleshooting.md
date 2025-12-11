# Troubleshooting Guide

## Common Issues and Solutions

### Deployment Issues

#### 1. Subnet Creation Fails: "AnotherOperationInProgress"

**Error:**
```
(AnotherOperationInProgress) Another operation on this or dependent resource is in progress.
```

**Cause:** Attempting to create multiple subnets on the same VNet in parallel.

**Solution:** Create subnets sequentially on the same VNet:
```bash
# WRONG - parallel subnet creation on same VNet
az network vnet subnet create ... --vnet-name vnet-hub &
az network vnet subnet create ... --vnet-name vnet-hub &  # FAILS

# CORRECT - sequential subnet creation
az network vnet subnet create ... --vnet-name vnet-hub
az network vnet subnet create ... --vnet-name vnet-hub
```

---

#### 2. Storage Account Name Already Taken

**Error:**
```
(StorageAccountAlreadyTaken) The storage account named stfilesyncprod001 is already taken.
```

**Cause:** Storage account names must be globally unique across all Azure subscriptions.

**Solution:** Add a unique suffix to storage account names:
```bash
UNIQUE_SUFFIX=$(date +%s | tail -c 6)
STORAGE_NAME="stalzprod${UNIQUE_SUFFIX}"
```

---

#### 3. Git Bash Path Translation Error

**Error:**
Resource IDs like `/subscriptions/...` become `C:/Program Files/Git/subscriptions/...`

**Cause:** Git Bash translates paths starting with `/` to Windows paths.

**Solution:** Use PowerShell wrapper for commands with resource IDs:
```bash
if [ -n "$MSYSTEM" ]; then
    powershell -Command "az network vnet peering create ... --remote-vnet '$VNET_ID'"
else
    az network vnet peering create ... --remote-vnet "$VNET_ID"
fi
```

---

#### 4. Firewall Private IP is Null

**Error:**
```
FW_IP is empty or null after firewall creation
```

**Cause:** Firewall created with `--no-wait` may not have IP configuration ready.

**Solution:** Wait for firewall or explicitly verify IP configuration:
```bash
# Wait for firewall to complete
az network firewall create ... # WITHOUT --no-wait

# Or verify IP config exists
FW_IP=$(az network firewall show -g $RG -n $FW_NAME \
  --query "ipConfigurations[0].privateIPAddress" -o tsv)

if [ -z "$FW_IP" ] || [ "$FW_IP" = "null" ]; then
    # Create IP config explicitly
    az network firewall ip-config create ...
fi
```

---

#### 5. VM_ADMIN_PASSWORD Not Set

**Error:**
```
ERROR: VM_ADMIN_PASSWORD environment variable is required
```

**Cause:** Script requires password via environment variable for security.

**Solution:**
```bash
export VM_ADMIN_PASSWORD='YourSecureP@ssw0rd123!'
./scripts/deploy-local.sh prod eastus 2
```

---

### Connectivity Issues

#### 1. Spoke-to-Spoke Connectivity Fails

**Symptoms:**
- VMs in different spokes cannot ping each other
- Connectivity test shows "Unreachable"

**Diagnostic Steps:**

1. **Check VNet Peering Status:**
```bash
az network vnet peering list -g rg-hub-networking-prod-eastus-001 \
  --vnet-name vnet-hub-prod-eastus-001 -o table
```
Status should be "Connected"

2. **Check Route Tables:**
```bash
az network route-table route list -g rg-spoke1-prod-eastus-001 \
  --route-table-name rt-spoke1-to-hub -o table
```
Verify routes to other spokes point to firewall IP

3. **Check Firewall Rules:**
```bash
az network firewall network-rule list -g rg-hub-networking-prod-eastus-001 \
  --firewall-name fw-hub-prod-eastus-001 -o table
```
Verify AllowSpokeToSpoke rule exists

4. **Check NSG Rules:**
```bash
az network nsg rule list -g rg-spoke1-prod-eastus-001 \
  --nsg-name nsg-spoke1-workloads-001 -o table
```
Verify Allow-VNet-Inbound and Allow-VNet-Outbound rules

---

#### 2. Cannot Connect via Azure Bastion

**Symptoms:**
- Bastion connection times out
- "Target VM not found" error

**Diagnostic Steps:**

1. **Check Bastion Status:**
```bash
az network bastion show -g rg-hub-networking-prod-eastus-001 \
  -n bastion-hub-prod-eastus-001 --query provisioningState
```
Should be "Succeeded"

2. **Check VM Network Interface:**
```bash
az vm show -g rg-spoke1-prod-eastus-001 -n vm-workload-prod-001 \
  --query "networkProfile.networkInterfaces[0].id"
```

3. **Verify No Public IP on VM:**
VMs should NOT have public IPs for Bastion to work correctly

---

#### 3. Internet Access from VMs Not Working

**Symptoms:**
- VMs cannot reach internet
- DNS resolution fails

**Solution:**

1. **Check Default Route:**
```bash
az network nic show-effective-route-table \
  -g rg-spoke1-prod-eastus-001 -n vm-workload-prod-001VMNic
```
Verify 0.0.0.0/0 routes to firewall or internet gateway

2. **Check Firewall Application Rules:**
If using Azure Firewall, ensure application rules allow outbound HTTP/HTTPS

---

### GitHub Actions Issues

#### 1. Azure Login Fails

**Error:**
```
Error: Login failed with Error: The subscription ID could not be found
```

**Solution:**
1. Verify AZURE_CREDENTIALS secret is properly formatted JSON
2. Check service principal hasn't expired:
```bash
az ad sp show --id <app-id> --query "passwordCredentials[].endDateTime"
```

---

#### 2. Workflow Timeout

**Error:**
```
The job running on runner GitHub Actions has exceeded the maximum execution time of 360 minutes.
```

**Cause:** VPN Gateway deployment takes 20-40 minutes alone.

**Solution:**
- Skip VPN Gateway for faster deployments
- Increase timeout in workflow:
```yaml
jobs:
  deploy:
    timeout-minutes: 120
```

---

#### 3. Quota Exceeded

**Error:**
```
(OperationNotAllowed) Operation could not be completed as it results in exceeding approved Total Regional Cores quota.
```

**Solution:**
1. Check current quota:
```bash
az vm list-usage --location eastus -o table
```

2. Request quota increase via Azure Portal or:
```bash
az quota update --resource-name standardBSFamily \
  --scope /subscriptions/{sub-id}/providers/Microsoft.Compute/locations/eastus \
  --limit-object value=100
```

---

### Cleanup Issues

#### 1. Resource Group Deletion Stuck

**Symptoms:**
- `az group delete` runs for extended time
- Resources remain after deletion command

**Cause:** Resources with dependencies or locks preventing deletion.

**Solution:**
1. **Check for Locks:**
```bash
az lock list -g rg-hub-networking-prod-eastus-001
```

2. **Delete Locks First:**
```bash
az lock delete --name <lock-name> -g <resource-group>
```

3. **Force Delete with Purge:**
```bash
az group delete -n rg-hub-networking-prod-eastus-001 --yes --force-deletion-types Microsoft.Compute/virtualMachines
```

---

## Diagnostic Commands

### Network Diagnostics

```bash
# Check effective routes
az network nic show-effective-route-table -g $RG -n $NIC_NAME

# Check effective NSG rules
az network nic list-effective-nsg -g $RG -n $NIC_NAME

# Test connectivity (requires Network Watcher extension)
az network watcher test-connectivity \
  -g $SOURCE_RG --source-resource $SOURCE_VM \
  --dest-address $DEST_IP --dest-port 22

# Check peering status
az network vnet peering show -g $RG --vnet-name $VNET -n $PEERING_NAME
```

### Firewall Diagnostics

```bash
# Check firewall status
az network firewall show -g $RG -n $FW_NAME --query "{status:provisioningState, ip:ipConfigurations[0].privateIPAddress}"

# List network rules
az network firewall network-rule collection list -g $RG --firewall-name $FW_NAME

# Check firewall logs (requires diagnostic settings)
az monitor log-analytics query -w $WORKSPACE_ID --analytics-query "
AzureDiagnostics
| where Category == 'AzureFirewallNetworkRule'
| project TimeGenerated, msg_s
| take 50"
```

### VM Diagnostics

```bash
# Check VM status
az vm get-instance-view -g $RG -n $VM_NAME --query "instanceView.statuses[1].displayStatus"

# Check VM extensions
az vm extension list -g $RG --vm-name $VM_NAME -o table

# Get boot diagnostics
az vm boot-diagnostics get-boot-log -g $RG -n $VM_NAME
```

---

## Getting Help

1. **Azure Support:** Create support ticket in Azure Portal
2. **GitHub Issues:** [ALZ-v3 Issues](https://github.com/yolomcdolo/ALZ-v3/issues)
3. **Azure Documentation:** [Hub-Spoke Topology](https://docs.microsoft.com/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)
