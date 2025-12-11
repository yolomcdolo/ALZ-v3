# Security Baseline

## Overview

This document defines the security baseline for ALZ-v3 deployments, aligned with Azure Security Benchmark and CIS Controls.

## Network Security

### Azure Firewall

| Control | Implementation | Status |
|---------|---------------|--------|
| Network segmentation | Spoke-to-spoke via Firewall | Implemented |
| Threat intelligence | Available on Standard tier | Optional |
| TLS inspection | Available on Premium tier | Optional |
| IDPS | Available on Premium tier | Optional |

**Default Rules:**
- Allow spoke-to-spoke communication
- Deny all other traffic by default

### Network Security Groups

| Rule | Priority | Direction | Source | Action |
|------|----------|-----------|--------|--------|
| Allow-VNet-Inbound | 100 | Inbound | 10.0.0.0/8 | Allow |
| Allow-VNet-Outbound | 100 | Outbound | 10.0.0.0/8 | Allow |
| DenyAllInbound | 4096 | Inbound | * | Deny |
| DenyAllOutbound | 4096 | Outbound | * | Deny |

### Private Endpoints

- VMs have no public IP addresses
- Access only through Azure Bastion
- Private endpoints recommended for PaaS services

## Identity & Access

### Service Principal

| Setting | Recommendation | Implementation |
|---------|---------------|----------------|
| Credential type | Certificate | Secret (improve to cert) |
| Expiration | 90 days max | Default 1 year |
| Permissions | Least privilege | Contributor (scope to RGs) |
| Rotation | Automated | Manual |

**Recommended Improvements:**
1. Use managed identity where possible
2. Implement credential rotation automation
3. Scope service principal to specific resource groups

### VM Access

| Method | Recommendation | Implementation |
|--------|---------------|----------------|
| SSH | Key-based only | Password (improve) |
| RDP | Bastion only | Bastion only |
| Admin username | Unique per env | Generic "azureadmin" |

**Recommended Improvements:**
1. Use SSH keys instead of passwords for Linux VMs
2. Implement Azure AD authentication for VMs
3. Use unique admin usernames per environment

## Secrets Management

### Current Implementation

| Secret | Storage | Recommendation |
|--------|---------|---------------|
| VM passwords | Environment variable | Azure Key Vault |
| Service principal | GitHub Secrets | Azure Key Vault + OIDC |
| Connection strings | N/A | Azure Key Vault |

### Target Implementation

```yaml
# Use Azure Key Vault for all secrets
- name: Get Secrets from Key Vault
  uses: Azure/get-keyvault-secrets@v1
  with:
    keyvault: "kv-alz-secrets-prod"
    secrets: 'vm-admin-password, storage-key'
```

## Compliance Frameworks

### Azure Security Benchmark Alignment

| Control | ASB ID | Status | Notes |
|---------|--------|--------|-------|
| Network segmentation | NS-1 | Compliant | Hub-spoke with firewall |
| DDoS protection | NS-5 | Partial | Basic only |
| Secure management | PA-2 | Compliant | Bastion access |
| Logging and monitoring | LT-1 | Partial | Log Analytics deployed |
| Vulnerability management | PV-1 | Not implemented | Add Defender |

### CIS Azure Benchmark Alignment

| Control | CIS ID | Status |
|---------|--------|--------|
| Ensure no public IP on VMs | 6.1 | Compliant |
| Ensure NSG flow logs enabled | 6.4 | Not implemented |
| Ensure network watcher enabled | 6.5 | Compliant |
| Ensure storage encryption | 7.1 | Default (compliant) |

## Security Monitoring

### Current Implementation

- Log Analytics workspace deployed
- Basic Azure Monitor metrics

### Recommended Additions

1. **Microsoft Defender for Cloud**
```bash
az security pricing create --name VirtualMachines --tier Standard
az security pricing create --name SqlServers --tier Standard
```

2. **Azure Sentinel** (SIEM)
```bash
az sentinel onboard --workspace-name log-hub-prod-eastus-001 -g rg-hub-networking-prod-eastus-001
```

3. **NSG Flow Logs**
```bash
az network watcher flow-log create \
  --nsg nsg-spoke1-workloads-001 \
  --workspace log-hub-prod-eastus-001 \
  --enabled true
```

## Encryption

### Data at Rest

| Resource | Encryption | Key Management |
|----------|-----------|----------------|
| VM OS Disks | SSE with PMK | Platform-managed |
| VM Data Disks | SSE with PMK | Platform-managed |
| Storage Accounts | SSE with PMK | Platform-managed |

**Recommended:** Enable customer-managed keys (CMK) for sensitive workloads.

### Data in Transit

| Connection | Encryption | Protocol |
|------------|-----------|----------|
| VM to VM (internal) | Not enforced | Application-level |
| VM to Azure services | TLS 1.2+ | HTTPS |
| Bastion to VM | TLS 1.2 | RDP/SSH over HTTPS |

## Vulnerability Management

### Current State

- No automated vulnerability scanning
- No patch management automation

### Recommendations

1. **Enable Azure Update Manager**
```bash
az maintenance configuration create \
  --name "WeeklyPatching" \
  --maintenance-scope InGuestPatch \
  --reboot-setting IfRequired
```

2. **Enable Defender for Servers**
```bash
az security pricing create --name VirtualMachines --tier Standard
```

3. **Enable Qualys extension**
```bash
az vm extension set \
  --name QualysAgent \
  --publisher Qualys \
  --vm-name vm-workload-prod-001
```

## Security Hardening Checklist

### Network
- [x] Hub-spoke with Azure Firewall
- [x] NSGs on all subnets
- [x] No public IPs on workload VMs
- [x] Bastion for VM access
- [ ] DDoS Protection Standard
- [ ] NSG Flow Logs enabled
- [ ] Azure Firewall Premium (IDPS)

### Identity
- [x] Service principal for automation
- [ ] Managed identities for VMs
- [ ] Azure AD authentication for VMs
- [ ] Privileged Identity Management (PIM)
- [ ] Conditional Access policies

### Data
- [x] Encryption at rest (default)
- [ ] Customer-managed keys
- [ ] Azure Key Vault for secrets
- [ ] Soft delete enabled

### Monitoring
- [x] Log Analytics workspace
- [ ] Diagnostic settings on all resources
- [ ] Microsoft Defender for Cloud
- [ ] Azure Sentinel
- [ ] Alert rules configured

### Compliance
- [ ] Azure Policy assignments
- [ ] Regulatory compliance dashboard
- [ ] Resource locks on production

## Security Score Target

| Category | Current | Target |
|----------|---------|--------|
| Network | 70% | 90% |
| Identity | 50% | 85% |
| Data | 60% | 90% |
| Monitoring | 40% | 80% |
| **Overall** | **55%** | **85%** |

## References

- [Azure Security Benchmark](https://docs.microsoft.com/azure/security/benchmarks/overview)
- [CIS Azure Benchmark](https://www.cisecurity.org/benchmark/azure)
- [Azure Well-Architected Framework - Security](https://docs.microsoft.com/azure/architecture/framework/security/)
