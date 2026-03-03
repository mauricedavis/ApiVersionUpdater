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

The application provides a modern, streamlined interface with step-based navigation:
- **Dashboard** - Compliance overview, version distribution, and Recent Sessions for quick access to previous work
- **Scan** - Real-time scan progress and status
- **Review** - Component findings with analysis results and alerts
- **Plan** - Change plan creation, validation, and deployment with test level options
- **Backup** - Component backup management, restore capability, and deployment history

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
- **Test Level Selection** - Choose from No Tests, Run Local Tests, or Run All Tests
- Backup creation before deployment (optional)
- Deployment of selected components only
- Real-time status tracking
- Detailed error messages for failed deployments
- **Smart Error Guidance** - Contextual help for common errors (CALLOUT_AFTER_DML, MIXED_DML, timeouts)
- **Manual Deployment Fallback** - Step-by-step instructions when automated deployment times out

#### Backup & Restore
- Automatic backup creation during deployment
- Preview backed-up component content
- Side-by-side diff comparison with current version
- Individual or bulk restore capability
- Backup expiration tracking (90 days)
- Deployment history with version change details and direct component links
- Manual restore workflow with "Copy Code" and "Open in Setup" options

#### Session Management
- Persistent session tracking across browser refreshes
- Current Session summary card showing scan, plan, and deployment status
- Progress stepper showing workflow stage
- Quick navigation between workflow steps

### User Interface
- Modern SLDS-compliant design
- **Step-based navigation** via interactive progress stepper (replaces tabs for cleaner UX)
- **Current Session card** showing scan, plan, and deployment status at a glance
- **Settings modal** accessible via gear icon in header
- **Recent Sessions** on Dashboard for quick access to previous work
- Status badges and color-coded indicators
- Responsive data tables with sorting, filtering, and row actions
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
2. Click the gear icon in the header to configure your target API version
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
   - Click the gear icon in the header to open Settings
   - Set your target API version (e.g., 56.0)
   - Choose scope policy (Custom Only, All, etc.)
   - Select component types to include

2. **Run Compliance Scan**
   - Click "Start Compliance Scan" from the Dashboard
   - Progress stepper automatically advances to Scan step
   - Wait for scan to complete (auto-advances to Review)

3. **Review Findings**
   - Review components needing upgrade in the findings list
   - Check for blocking issues (red alerts)
   - Filter by component type or severity

4. **Create Change Plan**
   - Click "Create Change Plan" from the Review step
   - Progress stepper advances to Plan step
   - Review eligible vs blocked components

5. **Validate & Deploy**
   - Select components to deploy
   - Click "Validate Selected" to check compilation
   - **Choose Test Level** (No Tests, Local Tests, or All Tests)
   - Enable backup option (recommended)
   - Click "Deploy Now" to apply changes

6. **Monitor & Restore (if needed)**
   - Check deployment status in Current Session card
   - Click Backup step to view deployment history
   - Restore individual components if needed

### Quick Actions

- **Resume Previous Work**: Click on any session in "Recent Sessions" on the Dashboard
- **Start Fresh**: Click "New Session" button in the Current Session card
- **Delete Old Scans**: Use the delete action in Recent Sessions table

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

### Version 1.2 (Current)
- **Consolidated Scan & Review** - Combined into a single "Scan" workflow step for a cleaner 3-step process (Scan → Plan → Deploy)
- **Enhanced Alert Display** - Alert column in findings shows version gap warnings with clickable links to scroll to findings
- **Version Gap Alerts** - Automatic alerts for components with large (>10) or moderate (>5) version gaps
- **Deployment Timeout Handling** - Smart detection of deployment timeouts with manual deployment workflow option
- **Manual Deployment Workflow** - When automated deployment times out, provides step-by-step instructions with "Open in Setup" links and "Mark as Deployed" functionality
- **Plan Reset Sync** - Reset Plan now properly clears deployment status from the Deploy card
- **Deployment History Links** - Direct "Open" links to components in Deployment History for single-click review
- **Extended API Version Range** - Support for legacy components down to API version 21.0
- **Improved Scan Performance** - Bulkified queries and pagination for large org inventories
- **Cancel Scan Fix** - Cancel button now properly stops running scans
- **Alert Count Sync** - Synchronized alert counts between Scan card and findings panel
- **Backup Error Handling** - Fixed "List has no rows" errors during backup creation

### Version 1.1
- **Simplified Navigation** - Replaced tab-based navigation with step-based workflow using the progress stepper
- **Test Level Selection** - Choose No Tests, Run Local Tests, or Run All Tests during deployment
- **Recent Sessions** - Moved scan history to Dashboard for quick access to previous work
- **Delete Scans** - Added ability to delete old scans from Recent Sessions
- **Settings Modal** - Moved settings to a modal dialog accessible via header icon
- **Improved Session Management** - Clearer "New Session" button with proper labeling
- **Enhanced Refresh** - Better cache-busting for scan history updates

### Version 1.0
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
