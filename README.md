# API Version Updater

A comprehensive Lightning Web Component application for Salesforce that inventories, analyzes, and orchestrates API version upgrades for metadata components.

## Overview

This tool helps Salesforce administrators and developers:
- **Inventory** all Apex classes, triggers, Visualforce pages, and other components with their current API versions
- **Analyze** components for upgrade risks, deprecated APIs, and breaking changes
- **Plan** controlled upgrades with dependency-aware deployment sequencing
- **Execute** validated deployments with full audit trails

## Features

### MVP (Phase 1 - Current)
- Complete data model for scan tracking, findings, and change plans
- Permission sets for role-based access (Scanner, Analyzer, Deployer Admin)
- Custom Metadata Types for extensible rule packs

### Planned Features
- Tooling API integration for component inventory
- Baseline comparison and drift detection
- Rule-based static analysis with severity scoring
- Dependency graph visualization
- Metadata API deployment orchestration

## Installation

### Prerequisites
- Salesforce CLI (`sf` command)
- A Salesforce sandbox or scratch org

### Deploy to Org
```bash
sf project deploy start --source-dir force-app --target-org YOUR_ORG_ALIAS
```

## Data Model

### Custom Objects
| Object | Purpose |
|--------|---------|
| `Scan__c` | Tracks inventory/analysis runs |
| `ArtifactSnapshot__c` | Component snapshots with API versions |
| `Finding__c` | Analysis findings with severity |
| `ChangePlan__c` | Upgrade plans with validation status |
| `ChangeItem__c` | Individual components in a plan |
| `DeploymentRun__c` | Deployment execution records |
| `AuditEvent__c` | Audit trail for compliance |

### Custom Metadata Types
| Type | Purpose |
|------|---------|
| `RulePack__mdt` | Collections of analysis rules |
| `Rule__mdt` | Individual pattern-matching rules |

### Permission Sets
| Permission Set | Access Level |
|----------------|--------------|
| `Scanner_ReadOnly` | View scan results only |
| `Analyzer` | Run scans and create plans |
| `Deployer_Admin` | Full admin including deployments |

## Architecture

The application follows a two-track design:

1. **Inventory/Analyze Track** (Safe, low permission)
   - Uses Tooling API for fast reads
   - Produces findings and recommendations
   - Exportable reports

2. **Deploy/Upgrade Track** (Admin-gated)
   - Uses Metadata API for changes
   - Dependency-aware deployment waves
   - Validation gates and rollback support

## Development

### Project Structure
```
force-app/
├── main/
│   └── default/
│       ├── objects/        # Custom objects and fields
│       ├── customMetadata/ # Rule pack definitions
│       ├── permissionsets/ # Access control
│       ├── classes/        # Apex services (planned)
│       └── lwc/            # UI components (planned)
```

### Running Tests
```bash
sf apex run test --target-org YOUR_ORG_ALIAS --code-coverage
```

## License

MIT License

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## Support

For issues and feature requests, please use the [GitHub Issues](https://github.com/mauricedavis/ApiVersionUpdater/issues) page.
