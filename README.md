# ALZ-v3 - Azure Landing Zone with CI/CD Pipelines

Enterprise-grade Azure Landing Zone deployment using the Azure Council of AI Agents with GitHub Actions CI/CD.

## Architecture

```
ALZ-v3/
├── .github/workflows/       # GitHub Actions CI/CD pipelines
│   ├── deploy-hub-spoke.yml # Main hub-spoke deployment
│   ├── validate-bicep.yml   # Bicep template validation
│   ├── destroy-infra.yml    # Infrastructure teardown
│   └── connectivity-test.yml # Post-deployment connectivity tests
├── agents/azure-council/    # AI Agent configurations
│   ├── council-chair.md     # Master orchestrator
│   ├── azure-architect.md   # Compute & core infrastructure
│   ├── network-engineer.md  # Networking specialist
│   ├── security-auditor.md  # Security testing
│   ├── identity-guardian.md # IAM & Entra ID
│   ├── data-steward.md      # Data services
│   ├── devops-engineer.md   # CI/CD specialist
│   ├── compliance-officer.md # Governance & compliance
│   ├── deployment-tester.md # Deployment testing
│   └── deployment-reviewer.md # Post-deployment analysis
├── bicep/modules/           # ALZ-Bicep modules
├── bicep/parameters/        # Environment parameters
├── scripts/                 # Deployment scripts
├── docs/                    # Documentation
└── deployments/             # Deployment outputs
```

## Quick Start

### Prerequisites

1. **Azure CLI** authenticated (`az login`)
2. **GitHub CLI** authenticated (`gh auth login`)
3. **Azure Service Principal** for GitHub Actions

### Setup Service Principal

```bash
# Create service principal with Contributor role
az ad sp create-for-rbac --name "sp-alz-v3-github" \
  --role contributor \
  --scopes /subscriptions/{subscription-id} \
  --sdk-auth > azure-credentials.json

# Add the JSON output as GitHub secret: AZURE_CREDENTIALS
```

### Configure GitHub Secrets

Required secrets:
- `AZURE_CREDENTIALS` - Service principal JSON
- `AZURE_SUBSCRIPTION_ID` - Target subscription
- `VM_ADMIN_PASSWORD` - VM administrator password

### Deploy via GitHub Actions

1. Go to **Actions** tab
2. Select **Deploy Hub-Spoke Infrastructure**
3. Click **Run workflow**
4. Configure deployment options
5. Monitor deployment progress

### Deploy via Claude Code

```bash
/azure Deploy a hub-spoke network with 2 spoke VNets, Azure Firewall, and Azure Bastion
```

## Deployment Workflow

The deployment follows these phases:

```
Phase 1: Pre-Flight Checks
├── Shell detection
├── Provider registration
├── Quota validation
└── Output directory setup

Phase 2: Foundation (Parallel)
├── Resource groups (5)
└── Log Analytics workspace

Phase 3: Hub Network
├── Hub VNet (10.0.0.0/16)
└── Subnets (sequential)

Phase 4: Hub Services (Parallel --no-wait)
├── Azure Firewall
├── Azure Bastion
└── VPN Gateway (optional)

Phase 5: Spoke Networks (Parallel)
├── Spoke VNets
└── Subnet configurations

Phase 6: Connectivity
├── VNet Peering (6 connections)
├── NSGs with auto-rules
├── Route tables with firewall routes
└── Firewall network rules

Phase 7: Compute (Parallel --no-wait)
├── Workload VMs
└── Domain controllers

Phase 8: Validation
├── Connectivity tests
└── Documentation generation
```

## CI/CD Pipelines

### deploy-hub-spoke.yml
Main deployment pipeline with full hub-spoke architecture.

**Triggers:**
- Manual dispatch with parameters
- Push to `main` branch (optional)

**Parameters:**
| Parameter | Default | Description |
|-----------|---------|-------------|
| environment | prod | Target environment |
| location | eastus | Azure region |
| deploy_vpn_gateway | false | Include VPN Gateway |
| spoke_count | 3 | Number of spoke VNets |

### validate-bicep.yml
Validates all Bicep templates on PR.

**Triggers:**
- Pull request to `main`
- Validates syntax and best practices

### destroy-infra.yml
Safely tears down deployed infrastructure.

**Triggers:**
- Manual dispatch only
- Requires explicit confirmation

### connectivity-test.yml
Post-deployment connectivity validation.

**Triggers:**
- After successful deployment
- Manual dispatch for testing

## Azure Council Agents

| Agent | Responsibility |
|-------|---------------|
| Council Chair | Master orchestrator, deployment coordination |
| Azure Architect | Compute, VMs, AKS, container solutions |
| Network Engineer | VNets, NSGs, Firewall, Private Endpoints |
| Security Auditor | Security testing, compliance validation |
| Identity Guardian | Entra ID, RBAC, Managed Identities |
| Data Steward | Storage, Databases, Backup |
| DevOps Engineer | CI/CD, Container Registry, Automation |
| Compliance Officer | Azure Policy, Tagging, Cost Management |
| Deployment Tester | Test execution, validation |
| Deployment Reviewer | Post-deployment analysis, improvements |

## Key Features

### Pre-Flight Checks (IMP-001 to IMP-004)
- Shell detection (Git Bash/PowerShell/Bash)
- Azure provider registration
- VM quota validation
- Output directory creation

### Hub-Spoke Auto-Configuration (IMP-007 to IMP-009)
- NSG rules for VNet traffic automatically configured
- Route tables with firewall routes auto-created
- Firewall spoke-to-spoke rules auto-applied

### Parallel Deployment (IMP-010)
- Independent resources deployed simultaneously
- ~44% deployment time reduction
- Uses `--no-wait` for long-running operations

### Connectivity Validation
- Network Watcher connectivity tests
- Spoke-to-spoke via firewall verification
- Automatic documentation generation

## Estimated Costs

| Resource | Monthly Cost |
|----------|-------------|
| Azure Firewall (Standard) | ~$875 |
| Azure Bastion (Basic) | ~$140 |
| VPN Gateway (optional) | ~$140 |
| VMs (6x B2s/D2s_v3) | ~$250 |
| Storage (2 accounts) | ~$20 |
| Log Analytics | ~$10 |
| **Total (without VPN)** | **~$1,295** |
| **Total (with VPN)** | **~$1,435** |

## Documentation

- [Deployment Guide](docs/deployment-guide.md)
- [Network Topology](docs/network-topology.md)
- [Security Baseline](docs/security-baseline.md)
- [Troubleshooting](docs/troubleshooting.md)

## Contributing

1. Fork the repository
2. Create feature branch
3. Make changes
4. Submit pull request
5. CI/CD validates Bicep templates

## License

MIT License - See [LICENSE](LICENSE) for details.
