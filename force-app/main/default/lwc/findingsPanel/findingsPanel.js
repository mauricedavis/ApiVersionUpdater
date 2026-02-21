import { LightningElement, api, track } from 'lwc';
import getNonCompliantComponents from '@salesforce/apex/ApiVersionUpdaterController.getNonCompliantComponents';

export default class FindingsPanel extends LightningElement {
    @api scanId;
    @api findings = [];
    @api findingsSummary = {};
    @api targetVersion;
    @api scopePolicy;

    @track nonCompliantData = null;
    @track isLoading = false;
    @track error = null;
    @track activeTab = 'all';
    @track severityFilter = 'all';
    @track categoryFilter = 'all';
    @track searchText = '';
    @track showOnlyAlerts = false;

    typeLabels = {
        'ApexClass': 'Apex Classes',
        'ApexTrigger': 'Apex Triggers',
        'ApexPage': 'Visualforce Pages',
        'ApexComponent': 'Visualforce Components'
    };

    typeIcons = {
        'ApexClass': 'standard:apex',
        'ApexTrigger': 'standard:apex_plugin',
        'ApexPage': 'standard:visualforce_page',
        'ApexComponent': 'standard:lightning_component'
    };

    severityOptions = [
        { label: 'All Severities', value: 'all' },
        { label: 'Critical', value: 'Critical' },
        { label: 'Warning', value: 'Warning' },
        { label: 'Info', value: 'Info' }
    ];

    categoryOptions = [
        { label: 'All Categories', value: 'all' },
        { label: 'Breaking Change', value: 'BreakingChange' },
        { label: 'Deprecation', value: 'Deprecation' },
        { label: 'Version Risk', value: 'VersionRisk' },
        { label: 'Drift', value: 'Drift' },
        { label: 'Code Quality', value: 'CodeQuality' }
    ];

    columns = [
        { label: 'Name', fieldName: 'recordUrl', type: 'url', sortable: true,
          typeAttributes: { 
            label: { fieldName: 'developerName' },
            target: '_blank',
            tooltip: 'Open in Salesforce Setup'
          },
          cellAttributes: { 
            iconName: { fieldName: 'alertIcon' },
            iconPosition: 'left',
            iconAlternativeText: { fieldName: 'alertReason' }
          }
        },
        { label: 'Current Version', fieldName: 'apiVersion', type: 'number', 
          typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 }, sortable: true },
        { label: 'Gap', fieldName: 'versionGap', type: 'number', sortable: true,
          cellAttributes: { class: { fieldName: 'gapClass' } } },
        { label: 'Alert', fieldName: 'alertReason', type: 'button', 
          typeAttributes: {
            label: { fieldName: 'alertReason' },
            name: 'viewAlert',
            variant: 'base',
            disabled: { fieldName: 'noAlert' }
          }
        },
        { label: 'Last Modified', fieldName: 'lastModifiedDate', type: 'date',
          typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } }
    ];

    connectedCallback() {
        this.loadNonCompliantComponents();
    }

    @api
    refresh() {
        this.loadNonCompliantComponents();
    }

    async loadNonCompliantComponents() {
        if (!this.targetVersion) {
            return;
        }

        this.isLoading = true;
        this.error = null;

        try {
            const result = await getNonCompliantComponents({
                targetApiVersion: parseFloat(this.targetVersion),
                scopePolicy: this.scopePolicy || 'CustomOnly'
            });

            const findingsMap = this.buildFindingsMap();

            const processedData = {
                totalCount: result.totalCount,
                targetApiVersion: result.targetApiVersion,
                countByType: result.countByType,
                byType: {}
            };

            for (const [type, artifacts] of Object.entries(result.byType)) {
                processedData.byType[type] = artifacts.map(a => {
                    const finding = findingsMap.get(a.fullName) || findingsMap.get(a.developerName);
                    return {
                        ...a,
                        versionGap: result.targetApiVersion - a.apiVersion,
                        gapClass: this.getGapClass(result.targetApiVersion - a.apiVersion),
                        hasFinding: !!finding,
                        alertIcon: finding ? this.getAlertIcon(finding.severity) : null,
                        alertReason: finding ? finding.summary : '',
                        alertSeverity: finding ? finding.severity : null,
                        alertCategory: finding ? finding.category : null,
                        alertFindingId: finding ? finding.id : null,
                        noAlert: !finding,
                        recordUrl: this.getRecordUrl(a.id, type)
                    };
                });
            }

            this.nonCompliantData = processedData;
        } catch (err) {
            console.error('Error loading non-compliant components:', err);
            this.error = err.body?.message || err.message || 'Unknown error';
        } finally {
            this.isLoading = false;
        }
    }

    buildFindingsMap() {
        const map = new Map();
        if (this.findings && this.findings.length > 0) {
            for (const finding of this.findings) {
                if (finding.artifactName) {
                    if (!map.has(finding.artifactName)) {
                        map.set(finding.artifactName, finding);
                    } else {
                        const existing = map.get(finding.artifactName);
                        if (this.getSeverityPriority(finding.severity) > this.getSeverityPriority(existing.severity)) {
                            map.set(finding.artifactName, finding);
                        }
                    }
                }
            }
        }
        return map;
    }

    getSeverityPriority(severity) {
        const priorities = { 'Critical': 3, 'Warning': 2, 'Info': 1 };
        return priorities[severity] || 0;
    }

    getAlertIcon(severity) {
        const icons = {
            'Critical': 'utility:error',
            'Warning': 'utility:warning',
            'Info': 'utility:info'
        };
        return icons[severity] || null;
    }

    getRecordUrl(recordId, artifactType) {
        if (!recordId) return null;
        
        const setupPaths = {
            'ApexClass': 'ApexClasses',
            'ApexTrigger': 'ApexTriggers',
            'ApexPage': 'ApexPages',
            'ApexComponent': 'ApexComponents'
        };
        
        const setupPath = setupPaths[artifactType];
        if (setupPath) {
            return `/lightning/setup/${setupPath}/page?address=%2F${recordId}`;
        }
        
        return `/${recordId}`;
    }

    getGapClass(gap) {
        if (gap >= 20) return 'slds-text-color_error';
        if (gap >= 10) return 'slds-text-color_warning';
        return '';
    }

    get hasNonCompliantData() {
        return this.nonCompliantData && this.nonCompliantData.totalCount > 0;
    }

    get totalNonCompliant() {
        return this.nonCompliantData?.totalCount || 0;
    }

    get apexClassCount() {
        return this.nonCompliantData?.countByType?.ApexClass || 0;
    }

    get apexTriggerCount() {
        return this.nonCompliantData?.countByType?.ApexTrigger || 0;
    }

    get apexPageCount() {
        return this.nonCompliantData?.countByType?.ApexPage || 0;
    }

    get apexComponentCount() {
        return this.nonCompliantData?.countByType?.ApexComponent || 0;
    }

    get alertCount() {
        if (!this.nonCompliantData) return 0;
        let count = 0;
        for (const artifacts of Object.values(this.nonCompliantData.byType)) {
            count += artifacts.filter(a => a.hasFinding).length;
        }
        return count;
    }

    get criticalAlertCount() {
        if (!this.nonCompliantData) return 0;
        let count = 0;
        for (const artifacts of Object.values(this.nonCompliantData.byType)) {
            count += artifacts.filter(a => a.alertSeverity === 'Critical').length;
        }
        return count;
    }

    get warningAlertCount() {
        if (!this.nonCompliantData) return 0;
        let count = 0;
        for (const artifacts of Object.values(this.nonCompliantData.byType)) {
            count += artifacts.filter(a => a.alertSeverity === 'Warning').length;
        }
        return count;
    }

    handleShowAlertsToggle(event) {
        this.showOnlyAlerts = event.target.checked;
    }

    get componentTypeTabs() {
        if (!this.nonCompliantData) return [];

        const tabs = [
            { 
                value: 'all', 
                label: `All (${this.totalNonCompliant})`,
                icon: 'utility:apps'
            }
        ];

        const types = ['ApexClass', 'ApexTrigger', 'ApexPage', 'ApexComponent'];
        for (const type of types) {
            const count = this.nonCompliantData.countByType[type] || 0;
            if (count > 0) {
                tabs.push({
                    value: type,
                    label: `${this.typeLabels[type]} (${count})`,
                    icon: this.typeIcons[type]
                });
            }
        }

        return tabs;
    }

    get filteredComponents() {
        if (!this.nonCompliantData) return [];

        let components = [];

        if (this.activeTab === 'all') {
            for (const type of Object.keys(this.nonCompliantData.byType)) {
                components = components.concat(
                    this.nonCompliantData.byType[type].map(c => ({
                        ...c,
                        typeLabel: this.typeLabels[type],
                        typeIcon: this.typeIcons[type]
                    }))
                );
            }
        } else {
            components = (this.nonCompliantData.byType[this.activeTab] || []).map(c => ({
                ...c,
                typeLabel: this.typeLabels[this.activeTab],
                typeIcon: this.typeIcons[this.activeTab]
            }));
        }

        if (this.showOnlyAlerts) {
            components = components.filter(c => c.hasFinding);
        }

        if (this.searchText) {
            const search = this.searchText.toLowerCase();
            components = components.filter(c => 
                c.developerName?.toLowerCase().includes(search) ||
                c.fullName?.toLowerCase().includes(search)
            );
        }

        components.sort((a, b) => {
            if (a.hasFinding && !b.hasFinding) return -1;
            if (!a.hasFinding && b.hasFinding) return 1;
            return a.apiVersion - b.apiVersion;
        });

        return components;
    }

    get groupedComponents() {
        if (!this.nonCompliantData || this.activeTab !== 'all') return null;

        const groups = [];
        const types = ['ApexClass', 'ApexTrigger', 'ApexPage', 'ApexComponent'];

        for (const type of types) {
            let artifacts = this.nonCompliantData.byType[type] || [];
            if (artifacts.length > 0) {
                let filteredArtifacts = [...artifacts];

                if (this.showOnlyAlerts) {
                    filteredArtifacts = filteredArtifacts.filter(c => c.hasFinding);
                }

                if (this.searchText) {
                    const search = this.searchText.toLowerCase();
                    filteredArtifacts = filteredArtifacts.filter(c => 
                        c.developerName?.toLowerCase().includes(search) ||
                        c.fullName?.toLowerCase().includes(search)
                    );
                }

                if (filteredArtifacts.length > 0) {
                    const alertCount = filteredArtifacts.filter(a => a.hasFinding).length;
                    groups.push({
                        type: type,
                        label: this.typeLabels[type],
                        icon: this.typeIcons[type],
                        count: filteredArtifacts.length,
                        alertCount: alertCount,
                        hasAlerts: alertCount > 0,
                        artifacts: filteredArtifacts.sort((a, b) => {
                            if (a.hasFinding && !b.hasFinding) return -1;
                            if (!a.hasFinding && b.hasFinding) return 1;
                            return a.apiVersion - b.apiVersion;
                        })
                    });
                }
            }
        }

        return groups;
    }

    get showGroupedView() {
        return this.activeTab === 'all';
    }

    get totalFindings() {
        return this.findings?.length || 0;
    }

    get criticalCount() {
        return this.findingsSummary?.Critical || 0;
    }

    get warningCount() {
        return this.findingsSummary?.Warning || 0;
    }

    get infoCount() {
        return this.findingsSummary?.Info || 0;
    }

    get hasFindings() {
        return this.findings && this.findings.length > 0;
    }

    get hasBlockingFindings() {
        return this.findings?.some(f => f.isBlocking) || false;
    }

    get filteredFindings() {
        let filtered = [...(this.findings || [])];

        if (this.severityFilter !== 'all') {
            filtered = filtered.filter(f => f.severity === this.severityFilter);
        }

        if (this.categoryFilter !== 'all') {
            filtered = filtered.filter(f => f.category === this.categoryFilter);
        }

        if (this.searchText) {
            const search = this.searchText.toLowerCase();
            filtered = filtered.filter(f => 
                f.artifactName?.toLowerCase().includes(search) ||
                f.summary?.toLowerCase().includes(search) ||
                f.ruleId?.toLowerCase().includes(search)
            );
        }

        return filtered.map(f => ({
            ...f,
            severityClass: this.getSeverityClass(f.severity),
            severityIcon: this.getSeverityIcon(f.severity)
        }));
    }

    getSeverityClass(severity) {
        const classMap = {
            'Critical': 'severity-critical',
            'Warning': 'severity-warning',
            'Info': 'severity-info'
        };
        return classMap[severity] || '';
    }

    getSeverityIcon(severity) {
        const iconMap = {
            'Critical': 'utility:error',
            'Warning': 'utility:warning',
            'Info': 'utility:info'
        };
        return iconMap[severity] || 'utility:info';
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
    }

    handleFilterChange(event) {
        const field = event.target.name;
        this[field] = event.target.value;
    }

    handleSearchChange(event) {
        this.searchText = event.target.value;
    }

    handleCreatePlan() {
        if (!this.scanId) {
            this.dispatchEvent(new CustomEvent('showerror', {
                detail: { message: 'No scan selected. Please run a compliance scan first before creating a change plan.' }
            }));
            return;
        }
        
        this.dispatchEvent(new CustomEvent('createplan', {
            detail: {
                scanId: this.scanId
            }
        }));
    }

    handleScrollToFindings() {
        const findingsSection = this.template.querySelector('.analysis-findings-section');
        if (findingsSection) {
            findingsSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        if (action.name === 'viewAlert' && row.alertFindingId) {
            this.scrollToFinding(row.developerName);
        }
    }

    scrollToFinding(artifactName) {
        const findingElement = this.template.querySelector(`[data-finding-name="${artifactName}"]`);
        if (findingElement) {
            findingElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
            findingElement.classList.add('highlight-finding');
            setTimeout(() => {
                findingElement.classList.remove('highlight-finding');
            }, 2000);
        } else {
            const findingsSection = this.template.querySelector('.analysis-findings-section');
            if (findingsSection) {
                findingsSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }
        }
    }

    get canCreatePlan() {
        return !!this.scanId;
    }

    get createPlanDisabledReason() {
        if (!this.scanId) {
            return 'Run a compliance scan first to create a change plan';
        }
        if (this.hasBlockingFindings) {
            return 'Cannot create plan with blocking findings';
        }
        return '';
    }
}
