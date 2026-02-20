import { LightningElement, api, track } from 'lwc';

export default class ScanPanel extends LightningElement {
    @api settings = {};
    @api recentScans = [];
    @api currentScan = null;

    @track scanConfig = {
        types: ['ApexClass', 'ApexTrigger', 'ApexPage', 'ApexComponent'],
        namespacePolicy: 'CustomOnly',
        targetApiVersion: '65.0',
        minApiVersion: null,
        maxApiVersion: null,
        baselineMode: 'LastScan',
        includeContent: true
    };

    apiVersionOptions = [];
    
    typeOptions = [
        { label: 'Apex Classes', value: 'ApexClass' },
        { label: 'Apex Triggers', value: 'ApexTrigger' },
        { label: 'Visualforce Pages', value: 'ApexPage' },
        { label: 'Visualforce Components', value: 'ApexComponent' }
    ];

    namespaceOptions = [
        { label: 'Custom Components Only', value: 'CustomOnly' },
        { label: 'Managed Packages Only', value: 'PackageOnly' },
        { label: 'All Components', value: 'All' }
    ];

    scanColumns = [
        { 
            label: 'Status', 
            fieldName: 'status', 
            type: 'text',
            cellAttributes: { class: { fieldName: 'statusClass' } }
        },
        { 
            label: 'Started', 
            fieldName: 'startedAt', 
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month: 'short',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            }
        },
        { 
            label: 'Findings', 
            fieldName: 'findingsCount', 
            type: 'number' 
        },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [
                    { label: 'View Results', name: 'view' }
                ]
            }
        }
    ];

    connectedCallback() {
        this.initializeFromSettings();
        this.generateApiVersionOptions();
    }

    initializeFromSettings() {
        if (this.settings) {
            this.scanConfig = {
                ...this.scanConfig,
                types: this.settings.includedTypes || this.scanConfig.types,
                namespacePolicy: this.settings.scopePolicy || this.scanConfig.namespacePolicy,
                targetApiVersion: this.settings.targetApiVersion || this.scanConfig.targetApiVersion
            };
        }
    }

    generateApiVersionOptions() {
        const options = [];
        for (let i = 65; i >= 45; i--) {
            options.push({ label: `API ${i}.0`, value: `${i}.0` });
        }
        this.apiVersionOptions = options;
    }

    get hasCurrentScan() {
        return this.currentScan !== null;
    }

    get isScanRunning() {
        return this.currentScan && 
               (this.currentScan.status === 'Queued' || this.currentScan.status === 'Running');
    }

    get currentScanStatusClass() {
        if (!this.currentScan) return '';
        const statusMap = {
            'Queued': 'status-badge status-queued',
            'Running': 'status-badge status-running',
            'Completed': 'status-badge status-completed',
            'Failed': 'status-badge status-failed',
            'Cancelled': 'status-badge status-failed'
        };
        return statusMap[this.currentScan.status] || 'status-badge';
    }

    get scanProgress() {
        if (!this.currentScan || !this.currentScan.totalArtifacts) return 0;
        return Math.round((this.currentScan.processedArtifacts / this.currentScan.totalArtifacts) * 100);
    }

    get hasRecentScans() {
        return this.recentScans && this.recentScans.length > 0;
    }

    get recentScansData() {
        return this.recentScans.map(scan => ({
            ...scan,
            findingsCount: scan.summary?.findingsCount || 0,
            statusClass: this.getStatusClass(scan.status)
        }));
    }

    getStatusClass(status) {
        const classMap = {
            'Queued': 'slds-text-color_weak',
            'Running': 'slds-text-color_default',
            'Completed': 'slds-text-color_success',
            'Failed': 'slds-text-color_error',
            'Cancelled': 'slds-text-color_error'
        };
        return classMap[status] || '';
    }

    handleConfigChange(event) {
        const field = event.target.name;
        const value = event.target.value;
        this.scanConfig = { ...this.scanConfig, [field]: value };
    }

    handleTypesChange(event) {
        this.scanConfig = { ...this.scanConfig, types: event.detail.value };
    }

    handleStartScan() {
        this.dispatchEvent(new CustomEvent('startscan', {
            detail: { ...this.scanConfig }
        }));
    }

    handleCancelScan() {
        if (this.currentScan) {
            this.dispatchEvent(new CustomEvent('cancelscan', {
                detail: { scanId: this.currentScan.scanId }
            }));
        }
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        if (action.name === 'view') {
            this.dispatchEvent(new CustomEvent('viewscan', {
                detail: { scanId: row.scanId }
            }));
        }
    }
}
