# API Version Updater

A comprehensive Lightning Web Component application for Salesforce that inventories, analyzes, and orchestrates API version upgrades for metadata components.

## Overview

This tool helps Salesforce administrators and developers:
- **Inventory** all Apex classes, triggers, Visualforce pages, and other components with their current API versions
- **Analyze** components for upgrade risks, deprecated APIs, and breaking changes
- **Plan** controlled upgrades with validation before deployment
- **Execute** validated deployments with full audit trails
- **Backup & Restore** components with the ability to rollback changes

## Screenshots

The application provides a modern, intuitive interface with:
- **Dashboard** - Overview of compliance metrics and version distribution
- **Scans & Findings** - Component inventory with analysis results
- **Change Plan** - Validation and deployment workflow
- **Backup & Restore** - Component backup management and deployment history

## Features

### Core Functionality (Implemented)

#### Dashboard & Inventory
- Real-time compliance metrics showing components needing upgrade
- Version distribution visualization across all component types
- Support for Apex Classes, Triggers, Visualforce Pages, Aura Components, and LWCs
- Configurable target API version and scope policies

#### Scanning & Analysis
- Automated component scanning via Salesforce Tooling API
- Analysis findings with severity levels (Critical, High, Medium, Low, Info)
- Detection of deprecated API usage and breaking changes
- Alerts for components with blocking issues
- Scan history with the ability to review previous scans

#### Change Plan Management
- Create change plans from scan results
- Filter by eligible vs blocked components
- Validation step before deployment
- Select specific components for deployment
- Reset and retry failed plans

#### Deployment Workflow
- Two-step validation and deploy process
- Backup creation before deployment (optional)
- Deployment of selected components only
- Real-time status tracking
- Detailed error messages for failed deployments

#### Backup & Restore
- Automatic backup creation during deployment
- Preview backed-up component content
- Side-by-side diff comparison with current version
- Individual or bulk restore capability
- Backup expiration tracking (90 days)
- Deployment history with version change details

#### Session Management
- Persistent session tracking across browser refreshes
- Current Session summary card showing scan, plan, and deployment status
- Progress stepper showing workflow stage
- Quick navigation between workflow steps

### User Interface
- Modern SLDS-compliant design
- Tabbed navigation with contextual icons
- Status badges and color-coded indicators
- Responsive data tables with sorting and filtering
- Modal dialogs for confirmations and previews
- Toast notifications for user feedback

## Installation

### Prerequisites
- Salesforce CLI (`sf` command)
- A Salesforce sandbox or scratch org with API version 55.0+
- System Administrator profile or equivalent permissions

### Deploy to Org
```bash
# Clone the repository
git clone https://github.com/mauricedavis/ApiVersionUpdater.git
cd ApiVersionUpdater

# Deploy to your org
sf project deploy start --source-dir force-app --target-org YOUR_ORG_ALIAS

# Assign permission set
sf org assign permset --name Deployer_Admin --target-org YOUR_ORG_ALIAS
```

### Post-Installation
1. Navigate to the App Launcher and search for "API Version Updater"
2. Configure your target API version in the Settings tab
3. Run your first compliance scan from the Dashboard

## Data Model

### Custom Objects
| Object | Purpose |
|--------|---------|
| `Scan__c` | Tracks inventory/analysis runs with status and summary |
| `ArtifactSnapshot__c` | Component snapshots with API versions from each scan |
| `Finding__c` | Analysis findings with severity and blocking indicators |
| `ChangePlan__c` | Upgrade plans with validation status and target version |
| `ChangeItem__c` | Individual components in a plan with apply status |
| `DeploymentRun__c` | Deployment execution records with results |
| `BackupItem__c` | Backed-up component content for restore |
| `UserSession__c` | User session state for workflow persistence |
| `AuditEvent__c` | Audit trail for compliance tracking |

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

### Apex Services
| Service | Purpose |
|---------|---------|
| `InventoryService` | Component inventory and compliance metrics |
| `ScanService` | Scan lifecycle management |
| `AnalysisService` | Component analysis and findings generation |
| `DeploymentService` | Change plan execution and deployment |
| `BackupService` | Backup creation and restore operations |
| `SessionService` | User session state management |
| `OrgContextService` | Org information and capabilities |
| `SettingsService` | Application configuration |

### Lightning Web Components
| Component | Purpose |
|-----------|---------|
| `apiVersionUpdater` | Main application container |
| `inventoryPanel` | Dashboard with compliance metrics |
| `scanPanel` | Scan execution and history |
| `findingsPanel` | Analysis findings display |
| `changePlanPanel` | Change plan management |
| `backupRestorePanel` | Backup and restore operations |
| `statusSummaryCard` | Current session summary |
| `progressStepper` | Workflow progress indicator |
| `sessionSelector` | Session history selector |

### Design Principles
1. **Safety First** - Validation before deployment, backups before changes
2. **Transparency** - Full audit trail, clear error messages, detailed history
3. **Flexibility** - Select specific components, reset and retry, restore from backup
4. **User Experience** - Intuitive workflow, persistent session, contextual guidance

## Usage Guide

### Typical Workflow

1. **Configure Settings**
   - Set your target API version (e.g., 55.0)
   - Choose scope policy (Custom Only, All, etc.)
   - Select component types to include

2. **Run Compliance Scan**
   - Click "Start Compliance Scan" from the Dashboard
   - Wait for scan to complete
   - Review compliance metrics and alerts

3. **Review Findings**
   - Navigate to Scans & Findings tab
   - Review components needing upgrade
   - Check for blocking issues (red alerts)

4. **Create Change Plan**
   - Click "Create Change Plan" 
   - Select target API version
   - Review eligible vs blocked components

5. **Validate & Deploy**
   - Select components to deploy
   - Click "Validate Selected" to check compilation
   - Enable backup option (recommended)
   - Click "Deploy Selected" to apply changes

6. **Monitor & Restore (if needed)**
   - Check deployment status in Current Session
   - View deployment history in Backup & Restore
   - Restore individual components if needed

## Development

### Project Structure
```
force-app/
├── main/
│   └── default/
│       ├── classes/        # Apex services
│       ├── lwc/            # Lightning Web Components
│       ├── objects/        # Custom objects and fields
│       ├── customMetadata/ # Rule pack definitions
│       └── permissionsets/ # Access control
```

### Running Tests
```bash
sf apex run test --target-org YOUR_ORG_ALIAS --code-coverage
```

### Local Development
```bash
# Watch for changes and deploy automatically
sf project deploy start --source-dir force-app --target-org YOUR_ORG_ALIAS --watch
```

## Changelog

### Version 1.0 (Current)
- Complete scan and analysis workflow
- Change plan creation and management
- Validation and deployment with selected components
- Backup creation and restore capability
- Session persistence across browser refreshes
- Deployment history tracking
- Detailed error messaging for failed deployments
- Reset and retry for failed plans

## License

MIT License

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Support

For issues and feature requests, please use the [GitHub Issues](https://github.com/mauricedavis/ApiVersionUpdater/issues) page.

## Acknowledgments

- Built with Salesforce Lightning Web Components
- Uses Salesforce Lightning Design System (SLDS)
- Inspired by the need for safer API version management in enterprise Salesforce orgs
