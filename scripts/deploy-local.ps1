<#
.SYNOPSIS
    Local deployment script for ALZ-v3 Hub-Spoke Architecture (PowerShell version)

.DESCRIPTION
    This script mirrors the GitHub Actions workflow for local execution on Windows.

.PARAMETER Environment
    Target environment (dev, staging, prod). Default: prod

.PARAMETER Location
    Azure region. Default: eastus

.PARAMETER SpokeCount
    Number of spoke VNets (2-5). Default: 3

.PARAMETER DeployVPN
    Deploy VPN Gateway. Default: $false

.PARAMETER DeployBastion
    Deploy Azure Bastion. Default: $true

.PARAMETER VMCountSpoke1
    Number of VMs in Spoke1. Default: 4

.PARAMETER VMCountSpoke2
    Number of VMs in Spoke2. Default: 2

.EXAMPLE
    $env:VM_ADMIN_PASSWORD = "YourSecureP@ss123!"
    .\deploy-local.ps1 -Environment prod -Location eastus -SpokeCount 2

.NOTES
    Requires Azure CLI installed and authenticated (az login)
    Requires VM_ADMIN_PASSWORD environment variable
#>

[CmdletBinding()]
param(
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "prod",

    [ValidateSet("eastus", "eastus2", "westus", "westus2", "centralus", "northeurope", "westeurope")]
    [string]$Location = "eastus",

    [ValidateRange(2, 5)]
    [int]$SpokeCount = 3,

    [bool]$DeployVPN = $false,

    [bool]$DeployBastion = $true,

    [ValidateRange(0, 10)]
    [int]$VMCountSpoke1 = 4,

    [ValidateRange(0, 10)]
    [int]$VMCountSpoke2 = 2
)

$ErrorActionPreference = "Stop"

# =============================================================================
# Helper Functions
# =============================================================================
function Write-Success { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host "WARNING: $Message" -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host "ERROR: $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host $Message }

function Test-AzureCLI {
    try {
        $null = az version 2>$null
        return $true
    }
    catch {
        return $false
    }
}

function Test-AzureAuth {
    try {
        $account = az account show 2>$null | ConvertFrom-Json
        return $null -ne $account
    }
    catch {
        return $false
    }
}

# =============================================================================
# Configuration
# =============================================================================
$Timestamp = Get-Date -Format "yyyyMMddHHmmss"
$DeploymentName = "alz-$Environment-$Timestamp"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "ALZ-v3 Local Deployment (PowerShell)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Info "Environment: $Environment"
Write-Info "Location: $Location"
Write-Info "Spokes: $SpokeCount"
Write-Info "VPN Gateway: $DeployVPN"
Write-Info "Bastion: $DeployBastion"
Write-Info "Deployment: $DeploymentName"
Write-Host "==========================================" -ForegroundColor Cyan

# =============================================================================
# Input Validation
# =============================================================================
Write-Host ""
Write-Info "Validating inputs..."

# Check VM_ADMIN_PASSWORD
if (-not $env:VM_ADMIN_PASSWORD) {
    Write-Error "VM_ADMIN_PASSWORD environment variable is required"
    Write-Error "Set it with: `$env:VM_ADMIN_PASSWORD = 'YourSecurePassword123!'"
    exit 1
}

if ($env:VM_ADMIN_PASSWORD.Length -lt 12) {
    Write-Error "VM_ADMIN_PASSWORD must be at least 12 characters"
    exit 1
}

Write-Success "All inputs validated"

# =============================================================================
# Pre-Flight Checks
# =============================================================================
Write-Host ""
Write-Host "Phase 1: Pre-Flight Checks" -ForegroundColor Yellow
Write-Host "--------------------------"

# Check Azure CLI
if (-not (Test-AzureCLI)) {
    Write-Error "Azure CLI not found. Install from https://aka.ms/installazurecliwindows"
    exit 1
}

# Check authentication
if (-not (Test-AzureAuth)) {
    Write-Error "Not authenticated. Run 'az login'"
    exit 1
}

Write-Success "Azure CLI authenticated"

# Provider registration
Write-Info "Checking Azure providers..."
$providers = @("Microsoft.Network", "Microsoft.Compute", "Microsoft.Storage", "Microsoft.OperationalInsights")

foreach ($provider in $providers) {
    $status = az provider show --namespace $provider --query "registrationState" -o tsv 2>$null
    if ($status -ne "Registered") {
        Write-Info "Registering $provider..."
        az provider register --namespace $provider --wait
    }
}
Write-Success "All providers registered"

# Quota check
Write-Info "Checking VM quota..."
$bQuota = az vm list-usage --location $Location --query "[?contains(name.value, 'standardBSFamily')].{current:currentValue, limit:limit}" -o tsv 2>$null
Write-Info "B-series quota: $bQuota"

Write-Success "Pre-flight checks passed"

# =============================================================================
# Phase 2: Foundation
# =============================================================================
Write-Host ""
Write-Host "Phase 2: Foundation" -ForegroundColor Yellow
Write-Host "-------------------"

$HubRG = "rg-hub-networking-$Environment-$Location-001"

Write-Info "Creating resource groups..."
az group create -n $HubRG -l $Location --tags Environment=$Environment ManagedBy=ALZ-v3-Local | Out-Null

$jobs = @()
for ($i = 1; $i -le $SpokeCount; $i++) {
    $jobs += Start-Job -ScriptBlock {
        param($rg, $loc, $env)
        az group create -n $rg -l $loc --tags Environment=$env ManagedBy=ALZ-v3-Local
    } -ArgumentList "rg-spoke$i-$Environment-$Location-001", $Location, $Environment
}

$jobs += Start-Job -ScriptBlock {
    param($rg, $loc, $env)
    az group create -n $rg -l $loc --tags Environment=$env ManagedBy=ALZ-v3-Local
} -ArgumentList "rg-shared-$Environment-$Location-001", $Location, $Environment

$jobs | Wait-Job | Out-Null
$jobs | Remove-Job

Write-Success "Resource groups created"

# Create Log Analytics
Write-Info "Creating Log Analytics workspace..."
az monitor log-analytics workspace create -g $HubRG -n "log-hub-$Environment-$Location-001" --retention-time 30 --query id -o tsv | Out-Null

Write-Success "Foundation deployed"

# =============================================================================
# Phase 3: Hub Network
# =============================================================================
Write-Host ""
Write-Host "Phase 3: Hub Network" -ForegroundColor Yellow
Write-Host "--------------------"

$HubVNet = "vnet-hub-$Environment-$Location-001"

Write-Info "Creating hub VNet..."
az network vnet create -g $HubRG -n $HubVNet --address-prefix 10.0.0.0/16 | Out-Null

# Subnets (sequential - same VNet requirement)
Write-Info "Creating subnets (sequential)..."
az network vnet subnet create -g $HubRG --vnet-name $HubVNet -n AzureFirewallSubnet --address-prefix 10.0.1.0/26 | Out-Null
az network vnet subnet create -g $HubRG --vnet-name $HubVNet -n AzureBastionSubnet --address-prefix 10.0.2.0/26 | Out-Null
az network vnet subnet create -g $HubRG --vnet-name $HubVNet -n snet-management --address-prefix 10.0.3.0/24 | Out-Null
az network vnet subnet create -g $HubRG --vnet-name $HubVNet -n snet-private-endpoints --address-prefix 10.0.4.0/24 | Out-Null

Write-Success "Hub VNet created with 4 subnets"

# =============================================================================
# Phase 4: Hub Services
# =============================================================================
Write-Host ""
Write-Host "Phase 4: Hub Services" -ForegroundColor Yellow
Write-Host "---------------------"

# Public IPs
Write-Info "Creating public IPs..."
$pipJobs = @()
$pipJobs += Start-Job -ScriptBlock {
    param($rg, $name)
    az network public-ip create -g $rg -n $name --sku Standard --allocation-method Static
} -ArgumentList $HubRG, "pip-fw-$Environment-$Location-001"

if ($DeployBastion) {
    $pipJobs += Start-Job -ScriptBlock {
        param($rg, $name)
        az network public-ip create -g $rg -n $name --sku Standard --allocation-method Static
    } -ArgumentList $HubRG, "pip-bastion-$Environment-$Location-001"
}

$pipJobs | Wait-Job | Out-Null
$pipJobs | Remove-Job
Write-Success "Public IPs created"

# Azure Firewall
Write-Info "Deploying Azure Firewall (this may take several minutes)..."
az network firewall create -g $HubRG -n "fw-hub-$Environment-$Location-001" -l $Location --sku AZFW_VNet --tier Standard --vnet-name $HubVNet --public-ip "pip-fw-$Environment-$Location-001" | Out-Null

$FwIP = az network firewall show -g $HubRG -n "fw-hub-$Environment-$Location-001" --query "ipConfigurations[0].privateIPAddress" -o tsv
Write-Success "Firewall deployed with private IP: $FwIP"

# Azure Bastion
if ($DeployBastion) {
    Write-Info "Deploying Azure Bastion..."
    az network bastion create -g $HubRG -n "bastion-hub-$Environment-$Location-001" --vnet-name $HubVNet --public-ip-address "pip-bastion-$Environment-$Location-001" --sku Basic --no-wait | Out-Null
    Write-Info "Bastion deployment started"
}

# =============================================================================
# Phase 5: Spoke Networks
# =============================================================================
Write-Host ""
Write-Host "Phase 5: Spoke Networks" -ForegroundColor Yellow
Write-Host "-----------------------"

$spokeJobs = @()
for ($i = 1; $i -le $SpokeCount; $i++) {
    $SpokeRG = "rg-spoke$i-$Environment-$Location-001"
    $SpokeVNet = "vnet-spoke$i-$Environment-$Location-001"
    $SubnetName = switch ($i) {
        1 { "snet-workloads" }
        2 { "snet-domain-controllers" }
        default { "snet-future" }
    }

    $spokeJobs += Start-Job -ScriptBlock {
        param($rg, $vnet, $subnet, $i)
        az network vnet create -g $rg -n $vnet --address-prefix "10.$i.0.0/16" --subnet-name $subnet --subnet-prefix "10.$i.1.0/24"
    } -ArgumentList $SpokeRG, $SpokeVNet, $SubnetName, $i
}

$spokeJobs | Wait-Job | Out-Null
$spokeJobs | Remove-Job
Write-Success "Spoke VNets created"

# =============================================================================
# Phase 6: Connectivity
# =============================================================================
Write-Host ""
Write-Host "Phase 6: Connectivity" -ForegroundColor Yellow
Write-Host "---------------------"

# VNet Peering
Write-Info "Creating VNet peerings..."
$HubVNetID = az network vnet show -g $HubRG -n $HubVNet --query id -o tsv

$peerJobs = @()
for ($i = 1; $i -le $SpokeCount; $i++) {
    $SpokeRG = "rg-spoke$i-$Environment-$Location-001"
    $SpokeVNet = "vnet-spoke$i-$Environment-$Location-001"
    $SpokeVNetID = az network vnet show -g $SpokeRG -n $SpokeVNet --query id -o tsv

    $peerJobs += Start-Job -ScriptBlock {
        param($hubRg, $hubVnet, $spokeVnetId, $i)
        az network vnet peering create -g $hubRg -n "peer-hub-to-spoke$i" --vnet-name $hubVnet --remote-vnet $spokeVnetId --allow-vnet-access --allow-forwarded-traffic
    } -ArgumentList $HubRG, $HubVNet, $SpokeVNetID, $i

    $peerJobs += Start-Job -ScriptBlock {
        param($spokeRg, $spokeVnet, $hubVnetId, $i)
        az network vnet peering create -g $spokeRg -n "peer-spoke$i-to-hub" --vnet-name $spokeVnet --remote-vnet $hubVnetId --allow-vnet-access --allow-forwarded-traffic
    } -ArgumentList $SpokeRG, $SpokeVNet, $HubVNetID, $i
}

$peerJobs | Wait-Job | Out-Null
$peerJobs | Remove-Job
Write-Success "VNet peerings created"

# NSGs
Write-Info "Creating NSGs with hub-spoke rules..."
$nsgJobs = @()
for ($i = 1; $i -le $SpokeCount; $i++) {
    $SpokeRG = "rg-spoke$i-$Environment-$Location-001"
    $NSGName = switch ($i) {
        1 { "nsg-spoke$i-workloads-001" }
        2 { "nsg-spoke$i-dc-001" }
        default { "nsg-spoke$i-future-001" }
    }

    $nsgJobs += Start-Job -ScriptBlock {
        param($rg, $nsg, $loc)
        az network nsg create -g $rg -n $nsg -l $loc
        az network nsg rule create -g $rg --nsg-name $nsg --name "Allow-VNet-Inbound" --priority 100 --direction Inbound --source-address-prefixes "10.0.0.0/8" --destination-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --access Allow
        az network nsg rule create -g $rg --nsg-name $nsg --name "Allow-VNet-Outbound" --priority 100 --direction Outbound --source-address-prefixes "*" --destination-address-prefixes "10.0.0.0/8" --destination-port-ranges "*" --protocol "*" --access Allow
    } -ArgumentList $SpokeRG, $NSGName, $Location
}

$nsgJobs | Wait-Job | Out-Null
$nsgJobs | Remove-Job
Write-Success "NSGs created"

# Route Tables
Write-Info "Creating route tables..."
$rtJobs = @()
for ($i = 1; $i -le $SpokeCount; $i++) {
    $SpokeRG = "rg-spoke$i-$Environment-$Location-001"
    $RTName = "rt-spoke$i-to-hub"

    $rtJobs += Start-Job -ScriptBlock {
        param($rg, $rt, $loc, $fwIp, $spokeCount, $currentSpoke)
        az network route-table create -g $rg -n $rt -l $loc
        for ($j = 1; $j -le $spokeCount; $j++) {
            if ($j -ne $currentSpoke) {
                az network route-table route create -g $rg --route-table-name $rt --name "to-spoke$j" --address-prefix "10.$j.0.0/16" --next-hop-type VirtualAppliance --next-hop-ip-address $fwIp
            }
        }
    } -ArgumentList $SpokeRG, $RTName, $Location, $FwIP, $SpokeCount, $i
}

$rtJobs | Wait-Job | Out-Null
$rtJobs | Remove-Job
Write-Success "Route tables created"

# Firewall rules
Write-Info "Configuring firewall spoke-to-spoke rules..."
$SpokeCIDRs = (1..$SpokeCount | ForEach-Object { "10.$_.0.0/16" }) -join " "

az network firewall network-rule create -g $HubRG --firewall-name "fw-hub-$Environment-$Location-001" --collection-name "AllowSpokeToSpoke" --name "Allow-All-Spokes" --protocols Any --source-addresses $SpokeCIDRs --destination-addresses $SpokeCIDRs --destination-ports "*" --action Allow --priority 100 | Out-Null

Write-Success "Firewall rules configured"

# =============================================================================
# Phase 7: Compute
# =============================================================================
Write-Host ""
Write-Host "Phase 7: Compute" -ForegroundColor Yellow
Write-Host "----------------"

$vmJobs = @()

# Spoke1 VMs
if ($VMCountSpoke1 -gt 0) {
    Write-Info "Deploying Spoke1 VMs..."
    $Spoke1RG = "rg-spoke1-$Environment-$Location-001"
    $Spoke1VNet = "vnet-spoke1-$Environment-$Location-001"

    for ($i = 1; $i -le $VMCountSpoke1; $i++) {
        $VMName = "vm-workload-$Environment-$($i.ToString('000'))"
        $vmJobs += Start-Job -ScriptBlock {
            param($rg, $vm, $vnet, $pwd)
            az vm create -g $rg -n $vm --image Ubuntu2204 --size Standard_B2s --vnet-name $vnet --subnet snet-workloads --admin-username azureadmin --admin-password $pwd --public-ip-address "" --nsg "" --no-wait
        } -ArgumentList $Spoke1RG, $VMName, $Spoke1VNet, $env:VM_ADMIN_PASSWORD
    }
}

# Spoke2 VMs
if ($VMCountSpoke2 -gt 0) {
    Write-Info "Deploying Spoke2 VMs..."
    $Spoke2RG = "rg-spoke2-$Environment-$Location-001"
    $Spoke2VNet = "vnet-spoke2-$Environment-$Location-001"

    for ($i = 1; $i -le $VMCountSpoke2; $i++) {
        $VMName = "vm-dc-$Environment-$($i.ToString('000'))"
        $vmJobs += Start-Job -ScriptBlock {
            param($rg, $vm, $vnet, $pwd)
            az vm create -g $rg -n $vm --image Win2022Datacenter --size Standard_D2s_v3 --vnet-name $vnet --subnet snet-domain-controllers --admin-username azureadmin --admin-password $pwd --public-ip-address "" --nsg "" --no-wait
        } -ArgumentList $Spoke2RG, $VMName, $Spoke2VNet, $env:VM_ADMIN_PASSWORD
    }
}

if ($vmJobs.Count -gt 0) {
    $vmJobs | Wait-Job | Out-Null
    $vmJobs | Remove-Job
}

Write-Success "VM deployments initiated"

Write-Info "Waiting for VMs to provision..."
Start-Sleep -Seconds 120

Write-Info "Spoke1 VMs:"
az vm list -g "rg-spoke1-$Environment-$Location-001" --query "[].{name:name, state:provisioningState}" -o table

Write-Info "Spoke2 VMs:"
az vm list -g "rg-spoke2-$Environment-$Location-001" --query "[].{name:name, state:provisioningState}" -o table

# =============================================================================
# Phase 8: Validation
# =============================================================================
Write-Host ""
Write-Host "Phase 8: Validation" -ForegroundColor Yellow
Write-Host "-------------------"

Write-Info "Running connectivity test..."
$Spoke1RG = "rg-spoke1-$Environment-$Location-001"
$Spoke2RG = "rg-spoke2-$Environment-$Location-001"

$SourceVM = az vm list -g $Spoke1RG --query "[0].name" -o tsv
$DestIP = az vm list-ip-addresses -g $Spoke2RG --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv

Write-Info "Testing: $SourceVM -> $DestIP"

# Install Network Watcher extension
az vm extension set -g $Spoke1RG --vm-name $SourceVM --name NetworkWatcherAgentLinux --publisher Microsoft.Azure.NetworkWatcher | Out-Null

# Run test
$Result = az network watcher test-connectivity -g $Spoke1RG --source-resource $SourceVM --dest-address $DestIP --dest-port 22 --query "{status:connectionStatus, latency:avgLatencyInMs}" | ConvertFrom-Json

Write-Info "Result: Status=$($Result.status), Latency=$($Result.latency)ms"

if ($Result.status -eq "Reachable") {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Success "Connectivity test: PASSED"
    Write-Success "Latency: $($Result.latency)ms"
}
else {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host "DEPLOYMENT COMPLETED - CONNECTIVITY ISSUE" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Warning "Connectivity test: FAILED"
    Write-Warning "Please check NSGs, route tables, and firewall rules"
}

Write-Host ""
Write-Info "Deployment: $DeploymentName"
Write-Info "Duration: $([math]::Round(((Get-Date) - (Get-Date $Timestamp -Format "yyyyMMddHHmmss")).TotalSeconds)) seconds"
