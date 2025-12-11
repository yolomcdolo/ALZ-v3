#!/bin/bash
# Local deployment script for ALZ-v3 Hub-Spoke Architecture
# This script mirrors the GitHub Actions workflow for local execution
#
# USAGE:
#   ./deploy-local.sh [env] [location] [spoke_count] [deploy_vpn] [deploy_bastion] [vm_count_spoke1] [vm_count_spoke2]
#
# ENVIRONMENT VARIABLES:
#   VM_ADMIN_PASSWORD - Required. Password for VM admin accounts.
#   ALZ_CONFIG_FILE   - Optional. Path to config file (default: ./config/default.yaml)
#
# EXAMPLES:
#   VM_ADMIN_PASSWORD="MySecureP@ss123!" ./deploy-local.sh prod eastus 2 false true 3 2
#   export VM_ADMIN_PASSWORD="MySecureP@ss123!" && ./deploy-local.sh

set -e
set -o pipefail

# =============================================================================
# Color Output
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
warn() { echo -e "${YELLOW}WARNING: $1${NC}" >&2; }
success() { echo -e "${GREEN}$1${NC}"; }
info() { echo "$1"; }

# =============================================================================
# Configuration
# =============================================================================
ENV="${1:-prod}"
LOCATION="${2:-eastus}"
SPOKE_COUNT="${3:-3}"
DEPLOY_VPN="${4:-false}"
DEPLOY_BASTION="${5:-true}"
VM_COUNT_SPOKE1="${6:-4}"
VM_COUNT_SPOKE2="${7:-2}"

# =============================================================================
# Input Validation
# =============================================================================
validate_inputs() {
    local errors=0

    # Validate environment
    case "$ENV" in
        dev|staging|prod) ;;
        *)
            error "Invalid environment: $ENV. Must be one of: dev, staging, prod"
            errors=$((errors + 1))
            ;;
    esac

    # Validate location
    VALID_LOCATIONS="eastus eastus2 westus westus2 centralus northeurope westeurope"
    if ! echo "$VALID_LOCATIONS" | grep -qw "$LOCATION"; then
        error "Invalid location: $LOCATION. Valid: $VALID_LOCATIONS"
        errors=$((errors + 1))
    fi

    # Validate spoke count
    if ! [[ "$SPOKE_COUNT" =~ ^[2-5]$ ]]; then
        error "Invalid spoke count: $SPOKE_COUNT. Must be 2-5"
        errors=$((errors + 1))
    fi

    # Validate boolean inputs
    case "$DEPLOY_VPN" in
        true|false) ;;
        *)
            error "Invalid deploy_vpn: $DEPLOY_VPN. Must be true or false"
            errors=$((errors + 1))
            ;;
    esac

    case "$DEPLOY_BASTION" in
        true|false) ;;
        *)
            error "Invalid deploy_bastion: $DEPLOY_BASTION. Must be true or false"
            errors=$((errors + 1))
            ;;
    esac

    # Validate VM counts
    if ! [[ "$VM_COUNT_SPOKE1" =~ ^[0-9]+$ ]] || [ "$VM_COUNT_SPOKE1" -gt 10 ]; then
        error "Invalid vm_count_spoke1: $VM_COUNT_SPOKE1. Must be 0-10"
        errors=$((errors + 1))
    fi

    if ! [[ "$VM_COUNT_SPOKE2" =~ ^[0-9]+$ ]] || [ "$VM_COUNT_SPOKE2" -gt 10 ]; then
        error "Invalid vm_count_spoke2: $VM_COUNT_SPOKE2. Must be 0-10"
        errors=$((errors + 1))
    fi

    # CRITICAL: Validate VM_ADMIN_PASSWORD
    if [ -z "$VM_ADMIN_PASSWORD" ]; then
        error "VM_ADMIN_PASSWORD environment variable is required"
        error "Set it with: export VM_ADMIN_PASSWORD='YourSecurePassword123!'"
        errors=$((errors + 1))
    elif [ ${#VM_ADMIN_PASSWORD} -lt 12 ]; then
        error "VM_ADMIN_PASSWORD must be at least 12 characters"
        errors=$((errors + 1))
    fi

    if [ $errors -gt 0 ]; then
        error "$errors validation error(s) found. Aborting."
        exit 1
    fi

    success "All inputs validated"
}

TIMESTAMP=$(date +%Y%m%d%H%M%S)
DEPLOYMENT_NAME="alz-${ENV}-${TIMESTAMP}"

# =============================================================================
# Background Job Tracking
# =============================================================================
FAILED_JOBS=0
declare -a BG_PIDS=()

# Function to wait for background jobs and check status
wait_for_jobs() {
    local description="${1:-background jobs}"
    local failed=0
    for pid in "${BG_PIDS[@]}"; do
        if ! wait "$pid" 2>/dev/null; then
            failed=$((failed + 1))
        fi
    done
    BG_PIDS=()
    if [ $failed -gt 0 ]; then
        error "$failed $description failed"
        FAILED_JOBS=$((FAILED_JOBS + failed))
        return 1
    fi
    return 0
}

# Cleanup function for rollback on failure
cleanup_on_failure() {
    if [ "$1" != "0" ]; then
        warn "Deployment failed. Resources may need manual cleanup."
        warn "Resource groups created: rg-hub-networking-${ENV}-${LOCATION}-001"
        for i in $(seq 1 $SPOKE_COUNT); do
            warn "  rg-spoke${i}-${ENV}-${LOCATION}-001"
        done
        warn "To delete all resources, run: ./destroy-local.sh $ENV $LOCATION"
    fi
}

trap 'cleanup_on_failure $?' EXIT

echo "=========================================="
echo "ALZ-v3 Local Deployment"
echo "=========================================="
echo "Environment: $ENV"
echo "Location: $LOCATION"
echo "Spokes: $SPOKE_COUNT"
echo "VPN Gateway: $DEPLOY_VPN"
echo "Bastion: $DEPLOY_BASTION"
echo "Deployment: $DEPLOYMENT_NAME"
echo "=========================================="

# Run input validation FIRST
validate_inputs

# =============================================================================
# Pre-Flight Checks
# =============================================================================
echo ""
echo "Phase 1: Pre-Flight Checks"
echo "--------------------------"

# Check Azure CLI
if ! command -v az &> /dev/null; then
    error "Azure CLI not found"
    exit 1
fi

# Check authentication
if ! az account show &> /dev/null; then
    error "Not authenticated. Run 'az login'"
    exit 1
fi

success "Azure CLI authenticated"

# Shell detection
if [ -n "$MSYSTEM" ]; then
    SHELL_TYPE="gitbash"
    USE_POWERSHELL_WRAPPER=true
    echo "Shell: Git Bash (PowerShell wrapper enabled)"
elif [ -n "$PSVersionTable" ]; then
    SHELL_TYPE="powershell"
    USE_POWERSHELL_WRAPPER=false
    echo "Shell: PowerShell"
else
    SHELL_TYPE="bash"
    USE_POWERSHELL_WRAPPER=false
    echo "Shell: Bash"
fi

# Provider registration
echo "Checking Azure providers..."
PROVIDERS="Microsoft.Network Microsoft.Compute Microsoft.Storage Microsoft.OperationalInsights"
for provider in $PROVIDERS; do
    status=$(az provider show --namespace $provider --query "registrationState" -o tsv 2>/dev/null)
    if [ "$status" != "Registered" ]; then
        echo "Registering $provider..."
        az provider register --namespace $provider --wait
    fi
done
echo "All providers registered"

# Quota check
echo "Checking VM quota..."
B_QUOTA=$(az vm list-usage --location $LOCATION \
    --query "[?contains(name.value, 'standardBSFamily')].{current:currentValue, limit:limit}" \
    -o tsv 2>/dev/null || echo "N/A")
echo "B-series quota: $B_QUOTA"

echo "Pre-flight checks passed"

# =============================================================================
# Phase 2: Foundation
# =============================================================================
echo ""
echo "Phase 2: Foundation"
echo "-------------------"

HUB_RG="rg-hub-networking-${ENV}-${LOCATION}-001"

# Create resource groups
echo "Creating resource groups..."
az group create -n $HUB_RG -l $LOCATION --tags Environment=$ENV ManagedBy=ALZ-v3-Local

for i in $(seq 1 $SPOKE_COUNT); do
    az group create -n "rg-spoke${i}-${ENV}-${LOCATION}-001" -l $LOCATION \
        --tags Environment=$ENV ManagedBy=ALZ-v3-Local &
done

az group create -n "rg-shared-${ENV}-${LOCATION}-001" -l $LOCATION \
    --tags Environment=$ENV ManagedBy=ALZ-v3-Local &

wait
echo "Resource groups created"

# Create Log Analytics
echo "Creating Log Analytics workspace..."
az monitor log-analytics workspace create \
    -g $HUB_RG \
    -n "log-hub-${ENV}-${LOCATION}-001" \
    --retention-time 30 \
    --query id -o tsv

echo "Foundation deployed"

# =============================================================================
# Phase 3: Hub Network
# =============================================================================
echo ""
echo "Phase 3: Hub Network"
echo "--------------------"

HUB_VNET="vnet-hub-${ENV}-${LOCATION}-001"

echo "Creating hub VNet..."
az network vnet create \
    -g $HUB_RG \
    -n $HUB_VNET \
    --address-prefix 10.0.0.0/16

# Subnets (sequential - same VNet requirement)
echo "Creating subnets (sequential)..."
az network vnet subnet create -g $HUB_RG --vnet-name $HUB_VNET \
    -n AzureFirewallSubnet --address-prefix 10.0.1.0/26

az network vnet subnet create -g $HUB_RG --vnet-name $HUB_VNET \
    -n AzureBastionSubnet --address-prefix 10.0.2.0/26

az network vnet subnet create -g $HUB_RG --vnet-name $HUB_VNET \
    -n snet-management --address-prefix 10.0.3.0/24

az network vnet subnet create -g $HUB_RG --vnet-name $HUB_VNET \
    -n snet-private-endpoints --address-prefix 10.0.4.0/24

echo "Hub VNet created with 4 subnets"

# =============================================================================
# Phase 4: Hub Services
# =============================================================================
echo ""
echo "Phase 4: Hub Services"
echo "---------------------"

# Public IPs
echo "Creating public IPs..."
az network public-ip create -g $HUB_RG -n "pip-fw-${ENV}-${LOCATION}-001" \
    --sku Standard --allocation-method Static &

if [ "$DEPLOY_BASTION" = "true" ]; then
    az network public-ip create -g $HUB_RG -n "pip-bastion-${ENV}-${LOCATION}-001" \
        --sku Standard --allocation-method Static &
fi

wait
echo "Public IPs created"

# Azure Firewall
echo "Deploying Azure Firewall (this may take several minutes)..."
az network firewall create \
    -g $HUB_RG \
    -n "fw-hub-${ENV}-${LOCATION}-001" \
    -l $LOCATION \
    --sku AZFW_VNet \
    --tier Standard \
    --vnet-name $HUB_VNET \
    --public-ip "pip-fw-${ENV}-${LOCATION}-001"

FW_IP=$(az network firewall show -g $HUB_RG -n "fw-hub-${ENV}-${LOCATION}-001" \
    --query "ipConfigurations[0].privateIPAddress" -o tsv)
echo "Firewall deployed with private IP: $FW_IP"

# Azure Bastion
if [ "$DEPLOY_BASTION" = "true" ]; then
    echo "Deploying Azure Bastion..."
    az network bastion create \
        -g $HUB_RG \
        -n "bastion-hub-${ENV}-${LOCATION}-001" \
        --vnet-name $HUB_VNET \
        --public-ip-address "pip-bastion-${ENV}-${LOCATION}-001" \
        --sku Basic \
        --no-wait
    echo "Bastion deployment started"
fi

# =============================================================================
# Phase 5: Spoke Networks
# =============================================================================
echo ""
echo "Phase 5: Spoke Networks"
echo "-----------------------"

for i in $(seq 1 $SPOKE_COUNT); do
    SPOKE_RG="rg-spoke${i}-${ENV}-${LOCATION}-001"
    SPOKE_VNET="vnet-spoke${i}-${ENV}-${LOCATION}-001"

    case $i in
        1) SUBNET_NAME="snet-workloads" ;;
        2) SUBNET_NAME="snet-domain-controllers" ;;
        *) SUBNET_NAME="snet-future" ;;
    esac

    (
        az network vnet create \
            -g $SPOKE_RG \
            -n $SPOKE_VNET \
            --address-prefix "10.${i}.0.0/16" \
            --subnet-name $SUBNET_NAME \
            --subnet-prefix "10.${i}.1.0/24"
        echo "Created $SPOKE_VNET"
    ) &
done

wait
echo "Spoke VNets created"

# =============================================================================
# Phase 6: Connectivity
# =============================================================================
echo ""
echo "Phase 6: Connectivity"
echo "---------------------"

# VNet Peering
echo "Creating VNet peerings..."
HUB_VNET_ID=$(az network vnet show -g $HUB_RG -n $HUB_VNET --query id -o tsv)

for i in $(seq 1 $SPOKE_COUNT); do
    SPOKE_RG="rg-spoke${i}-${ENV}-${LOCATION}-001"
    SPOKE_VNET="vnet-spoke${i}-${ENV}-${LOCATION}-001"
    SPOKE_VNET_ID=$(az network vnet show -g $SPOKE_RG -n $SPOKE_VNET --query id -o tsv)

    # Use PowerShell wrapper if Git Bash
    if [ "$USE_POWERSHELL_WRAPPER" = "true" ]; then
        powershell -Command "az network vnet peering create -g '$HUB_RG' -n 'peer-hub-to-spoke${i}' --vnet-name '$HUB_VNET' --remote-vnet '$SPOKE_VNET_ID' --allow-vnet-access --allow-forwarded-traffic" &
        powershell -Command "az network vnet peering create -g '$SPOKE_RG' -n 'peer-spoke${i}-to-hub' --vnet-name '$SPOKE_VNET' --remote-vnet '$HUB_VNET_ID' --allow-vnet-access --allow-forwarded-traffic" &
    else
        az network vnet peering create -g $HUB_RG -n "peer-hub-to-spoke${i}" \
            --vnet-name $HUB_VNET --remote-vnet $SPOKE_VNET_ID \
            --allow-vnet-access --allow-forwarded-traffic &
        az network vnet peering create -g $SPOKE_RG -n "peer-spoke${i}-to-hub" \
            --vnet-name $SPOKE_VNET --remote-vnet $HUB_VNET_ID \
            --allow-vnet-access --allow-forwarded-traffic &
    fi
done

wait
echo "VNet peerings created"

# NSGs with auto-configuration
echo "Creating NSGs with hub-spoke rules..."
for i in $(seq 1 $SPOKE_COUNT); do
    SPOKE_RG="rg-spoke${i}-${ENV}-${LOCATION}-001"

    case $i in
        1) NSG_NAME="nsg-spoke${i}-workloads-001" ;;
        2) NSG_NAME="nsg-spoke${i}-dc-001" ;;
        *) NSG_NAME="nsg-spoke${i}-future-001" ;;
    esac

    (
        az network nsg create -g $SPOKE_RG -n $NSG_NAME -l $LOCATION

        # Auto-configure hub-spoke rules (IMP-007)
        az network nsg rule create -g $SPOKE_RG --nsg-name $NSG_NAME \
            --name "Allow-VNet-Inbound" --priority 100 --direction Inbound \
            --source-address-prefixes "10.0.0.0/8" --destination-address-prefixes "*" \
            --destination-port-ranges "*" --protocol "*" --access Allow

        az network nsg rule create -g $SPOKE_RG --nsg-name $NSG_NAME \
            --name "Allow-VNet-Outbound" --priority 100 --direction Outbound \
            --source-address-prefixes "*" --destination-address-prefixes "10.0.0.0/8" \
            --destination-port-ranges "*" --protocol "*" --access Allow

        echo "NSG $NSG_NAME configured"
    ) &
done

wait
echo "NSGs created"

# Route Tables
echo "Creating route tables..."
for i in $(seq 1 $SPOKE_COUNT); do
    SPOKE_RG="rg-spoke${i}-${ENV}-${LOCATION}-001"
    RT_NAME="rt-spoke${i}-to-hub"

    (
        az network route-table create -g $SPOKE_RG -n $RT_NAME -l $LOCATION

        for j in $(seq 1 $SPOKE_COUNT); do
            if [ $i -ne $j ]; then
                az network route-table route create -g $SPOKE_RG \
                    --route-table-name $RT_NAME \
                    --name "to-spoke${j}" \
                    --address-prefix "10.${j}.0.0/16" \
                    --next-hop-type VirtualAppliance \
                    --next-hop-ip-address $FW_IP
            fi
        done
        echo "Route table $RT_NAME configured"
    ) &
done

wait
echo "Route tables created"

# Firewall rules
echo "Configuring firewall spoke-to-spoke rules..."
SPOKE_CIDRS=""
for i in $(seq 1 $SPOKE_COUNT); do
    SPOKE_CIDRS="${SPOKE_CIDRS}10.${i}.0.0/16 "
done

az network firewall network-rule create \
    -g $HUB_RG \
    --firewall-name "fw-hub-${ENV}-${LOCATION}-001" \
    --collection-name "AllowSpokeToSpoke" \
    --name "Allow-All-Spokes" \
    --protocols Any \
    --source-addresses $SPOKE_CIDRS \
    --destination-addresses $SPOKE_CIDRS \
    --destination-ports "*" \
    --action Allow \
    --priority 100

echo "Firewall rules configured"

# =============================================================================
# Phase 7: Compute
# =============================================================================
echo ""
echo "Phase 7: Compute"
echo "----------------"

# Spoke1 VMs
echo "Deploying Spoke1 VMs..."
SPOKE1_RG="rg-spoke1-${ENV}-${LOCATION}-001"
SPOKE1_VNET="vnet-spoke1-${ENV}-${LOCATION}-001"

for i in $(seq 1 $VM_COUNT_SPOKE1); do
    VM_NAME="vm-workload-${ENV}-$(printf '%03d' $i)"
    az vm create \
        -g $SPOKE1_RG \
        -n $VM_NAME \
        --image Ubuntu2204 \
        --size Standard_B2s \
        --vnet-name $SPOKE1_VNET \
        --subnet snet-workloads \
        --admin-username azureadmin \
        --admin-password "$VM_ADMIN_PASSWORD" \
        --public-ip-address "" \
        --nsg "" \
        --no-wait &
    BG_PIDS+=($!)
done

# Spoke2 VMs
echo "Deploying Spoke2 VMs..."
SPOKE2_RG="rg-spoke2-${ENV}-${LOCATION}-001"
SPOKE2_VNET="vnet-spoke2-${ENV}-${LOCATION}-001"

for i in $(seq 1 $VM_COUNT_SPOKE2); do
    VM_NAME="vm-dc-${ENV}-$(printf '%03d' $i)"
    az vm create \
        -g $SPOKE2_RG \
        -n $VM_NAME \
        --image Win2022Datacenter \
        --size Standard_D2s_v3 \
        --vnet-name $SPOKE2_VNET \
        --subnet snet-domain-controllers \
        --admin-username azureadmin \
        --admin-password "$VM_ADMIN_PASSWORD" \
        --public-ip-address "" \
        --nsg "" \
        --no-wait &
    BG_PIDS+=($!)
done

wait_for_jobs "VM deployments" || warn "Some VMs may have failed to start"
success "VM deployments initiated"

echo "Waiting for VMs to provision..."
sleep 120

echo "Spoke1 VMs:"
az vm list -g $SPOKE1_RG --query "[].{name:name, state:provisioningState}" -o table

echo "Spoke2 VMs:"
az vm list -g $SPOKE2_RG --query "[].{name:name, state:provisioningState}" -o table

# =============================================================================
# Phase 8: Validation
# =============================================================================
echo ""
echo "Phase 8: Validation"
echo "-------------------"

echo "Running connectivity test..."
SOURCE_VM=$(az vm list -g $SPOKE1_RG --query "[0].name" -o tsv)
DEST_IP=$(az vm list-ip-addresses -g $SPOKE2_RG \
    --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)

echo "Testing: $SOURCE_VM -> $DEST_IP"

# Install Network Watcher extension
az vm extension set \
    -g $SPOKE1_RG \
    --vm-name $SOURCE_VM \
    --name NetworkWatcherAgentLinux \
    --publisher Microsoft.Azure.NetworkWatcher

# Run test
RESULT=$(az network watcher test-connectivity \
    -g $SPOKE1_RG \
    --source-resource $SOURCE_VM \
    --dest-address $DEST_IP \
    --dest-port 22 \
    --query "{status:connectionStatus, latency:avgLatencyInMs}" -o json)

echo "Result: $RESULT"

STATUS=$(echo $RESULT | jq -r '.status')
if [ "$STATUS" = "Reachable" ]; then
    echo ""
    echo "=========================================="
    echo "DEPLOYMENT SUCCESSFUL!"
    echo "=========================================="
    echo "Connectivity test: PASSED"
    echo "Latency: $(echo $RESULT | jq -r '.latency')ms"
else
    echo ""
    echo "=========================================="
    echo "DEPLOYMENT COMPLETED - CONNECTIVITY ISSUE"
    echo "=========================================="
    echo "Connectivity test: FAILED"
    echo "Please check NSGs, route tables, and firewall rules"
fi

echo ""
echo "Deployment: $DEPLOYMENT_NAME"
echo "Duration: $SECONDS seconds"
