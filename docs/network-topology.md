# Network Topology

## Overview

ALZ-v3 deploys a hub-spoke network topology using Azure networking services.

## Architecture Diagram

```
                              ┌─────────────────────────────────────────────┐
                              │           Internet / On-premises            │
                              └──────────────────────┬──────────────────────┘
                                                     │
                                                     │ Public IP
                                                     ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                  HUB VNET (10.0.0.0/16)                                │
│                              rg-hub-networking-{env}-{loc}-001                         │
│                                                                                        │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐         │
│  │  AzureFirewallSubnet │  │  AzureBastionSubnet  │  │    GatewaySubnet     │         │
│  │     10.0.1.0/26      │  │     10.0.2.0/26      │  │    10.0.255.0/27     │         │
│  │                      │  │                      │  │                      │         │
│  │  ┌────────────────┐  │  │  ┌────────────────┐  │  │  ┌────────────────┐  │         │
│  │  │ Azure Firewall │  │  │  │ Azure Bastion  │  │  │  │  VPN Gateway   │  │         │
│  │  │   (10.0.1.4)   │  │  │  │                │  │  │  │   (optional)   │  │         │
│  │  └────────────────┘  │  │  └────────────────┘  │  │  └────────────────┘  │         │
│  └──────────────────────┘  └──────────────────────┘  └──────────────────────┘         │
│                                                                                        │
│  ┌──────────────────────┐  ┌──────────────────────┐                                   │
│  │  snet-management     │  │ snet-private-endpts  │                                   │
│  │     10.0.3.0/24      │  │     10.0.4.0/24      │                                   │
│  └──────────────────────┘  └──────────────────────┘                                   │
│                                                                                        │
└──────────────────────────────────────┬─────────────────────────────────────────────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    │ VNet Peering     │ VNet Peering     │ VNet Peering
                    ▼                  ▼                  ▼
┌────────────────────────┐  ┌────────────────────────┐  ┌────────────────────────┐
│  SPOKE 1 (10.1.0.0/16) │  │  SPOKE 2 (10.2.0.0/16) │  │  SPOKE N (10.N.0.0/16) │
│   rg-spoke1-{env}-...  │  │   rg-spoke2-{env}-...  │  │   rg-spokeN-{env}-...  │
│                        │  │                        │  │                        │
│  ┌──────────────────┐  │  │  ┌──────────────────┐  │  │  ┌──────────────────┐  │
│  │  snet-workloads  │  │  │  │ snet-domain-ctrl │  │  │  │   snet-future    │  │
│  │   10.1.1.0/24    │  │  │  │   10.2.1.0/24    │  │  │  │   10.N.1.0/24    │  │
│  │                  │  │  │  │                  │  │  │  │                  │  │
│  │  ┌──────┐ ┌────┐ │  │  │  │  ┌──────┐ ┌────┐ │  │  │  │  ┌──────┐        │  │
│  │  │ VM1  │ │VM2 │ │  │  │  │  │ DC1  │ │DC2 │ │  │  │  │  │ VM   │        │  │
│  │  │Ubuntu│ │    │ │  │  │  │  │Win22 │ │    │ │  │  │  │  │      │        │  │
│  │  └──────┘ └────┘ │  │  │  │  └──────┘ └────┘ │  │  │  │  └──────┘        │  │
│  └──────────────────┘  │  │  └──────────────────┘  │  │  └──────────────────┘  │
│                        │  │                        │  │                        │
│  NSG: nsg-spoke1-...   │  │  NSG: nsg-spoke2-...   │  │  NSG: nsg-spokeN-...   │
│  RT:  rt-spoke1-to-hub │  │  RT:  rt-spoke2-to-hub │  │  RT:  rt-spokeN-to-hub │
└────────────────────────┘  └────────────────────────┘  └────────────────────────┘
```

## IP Address Allocation

### Hub VNet (10.0.0.0/16)

| Subnet | CIDR | Purpose | Usable IPs |
|--------|------|---------|------------|
| AzureFirewallSubnet | 10.0.1.0/26 | Azure Firewall | 59 |
| AzureBastionSubnet | 10.0.2.0/26 | Azure Bastion | 59 |
| snet-management | 10.0.3.0/24 | Management VMs | 251 |
| snet-private-endpoints | 10.0.4.0/24 | Private Endpoints | 251 |
| GatewaySubnet | 10.0.255.0/27 | VPN Gateway | 27 |

### Spoke VNets (10.{N}.0.0/16)

| Spoke | VNet CIDR | Workload Subnet | Purpose |
|-------|-----------|-----------------|---------|
| Spoke 1 | 10.1.0.0/16 | 10.1.1.0/24 | Ubuntu workloads |
| Spoke 2 | 10.2.0.0/16 | 10.2.1.0/24 | Windows DCs |
| Spoke 3 | 10.3.0.0/16 | 10.3.1.0/24 | Future expansion |
| Spoke 4 | 10.4.0.0/16 | 10.4.1.0/24 | Future expansion |
| Spoke 5 | 10.5.0.0/16 | 10.5.1.0/24 | Future expansion |

## Traffic Flow

### Spoke-to-Spoke Communication

All traffic between spokes routes through Azure Firewall for inspection:

```
Spoke1 VM (10.1.1.4)
    │
    │ UDR: 10.2.0.0/16 → 10.0.1.4
    ▼
Azure Firewall (10.0.1.4)
    │
    │ Network Rule: Allow Spoke-to-Spoke
    ▼
Spoke2 VM (10.2.1.6)
```

### Internet Egress

Outbound internet traffic routes through Azure Firewall:

```
Spoke VM
    │
    │ UDR: 0.0.0.0/0 → 10.0.1.4
    ▼
Azure Firewall
    │
    │ NAT to Public IP
    ▼
Internet
```

### On-Premises Connectivity (Optional)

With VPN Gateway deployed:

```
On-premises Network
    │
    │ IPsec VPN Tunnel
    ▼
VPN Gateway (10.0.255.4)
    │
    │ VNet Peering (Gateway Transit)
    ▼
Spoke VNets
```

## Network Security

### NSG Rules (Per Spoke)

| Rule | Direction | Priority | Source | Destination | Action |
|------|-----------|----------|--------|-------------|--------|
| Allow-VNet-Inbound | Inbound | 100 | 10.0.0.0/8 | * | Allow |
| Allow-VNet-Outbound | Outbound | 100 | * | 10.0.0.0/8 | Allow |
| DenyAllInbound | Inbound | 4096 | * | * | Deny |

### Firewall Rules

| Collection | Rule | Protocol | Source | Destination | Ports |
|------------|------|----------|--------|-------------|-------|
| AllowSpokeToSpoke | Allow-All-Spokes | Any | 10.{1-5}.0.0/16 | 10.{1-5}.0.0/16 | * |

## VNet Peering Configuration

| Peering | Allow VNet Access | Allow Forwarded Traffic | Allow Gateway Transit |
|---------|-------------------|------------------------|----------------------|
| Hub → Spoke | Yes | Yes | Yes (if VPN) |
| Spoke → Hub | Yes | Yes | Use Remote Gateway (if VPN) |

## Scaling Considerations

- Maximum 5 spokes supported by default (address space 10.1-5.0.0/16)
- Each spoke can have up to 251 workload IPs (/24 subnet)
- Hub supports up to 59 firewall instances (AzureFirewallSubnet)
- VPN Gateway supports 30 S2S tunnels (VpnGw1)

## Monitoring

- Azure Firewall diagnostics → Log Analytics workspace
- NSG Flow Logs → Storage Account (optional)
- Network Watcher → Connectivity tests
