import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getOrgContext from '@salesforce/apex/ApiVersionUpdaterController.getOrgContext';
import getSettings from '@salesforce/apex/ApiVersionUpdaterController.getSettings';
import saveSettings from '@salesforce/apex/ApiVersionUpdaterController.saveSettings';
import getAvailableApiVersions from '@salesforce/apex/ApiVersionUpdaterController.getAvailableApiVersions';
import getSupportedComponentTypes from '@salesforce/apex/ApiVersionUpdaterController.getSupportedComponentTypes';
import getInventoryCounts from '@salesforce/apex/ApiVersionUpdaterController.getInventoryCounts';
import getVersionDistribution from '@salesforce/apex/ApiVersionUpdaterController.getVersionDistribution';
import getRecentScans from '@salesforce/apex/ApiVersionUpdaterController.getRecentScans';
import startScan from '@salesforce/apex/ApiVersionUpdaterController.startScan';
import getScanStatus from '@salesforce/apex/ApiVersionUpdaterController.getScanStatus';
import cancelScan from '@salesforce/apex/ApiVersionUpdaterController.cancelScan';
import getFindingsByScan from '@salesforce/apex/ApiVersionUpdaterController.getFindingsByScan';
import getFindingsSummary from '@salesforce/apex/ApiVersionUpdaterController.getFindingsSummary';
import createChangePlan from '@salesforce/apex/ApiVersionUpdaterController.createChangePlan';
import getChangePlan from '@salesforce/apex/ApiVersionUpdaterController.getChangePlan';
import getChangeItems from '@salesforce/apex/ApiVersionUpdaterController.getChangeItems';
import executePlan from '@salesforce/apex/ApiVersionUpdaterController.executePlan';

export default class ApiVersionUpdater extends LightningElement {
    @track orgContext = {};
    @track settings = {
        includedTypes: ['ApexClass', 'ApexTrigger', 'ApexPage', 'ApexComponent'],
        scopePolicy: 'CustomOnly',
        targetApiVersion: '65.0',
        incrementPolicy: 'IncrementalOnly',
        maxDeltaPerDeploy: 6,
        validateOnlyDefault: true
    };
    @track inventoryCounts = {};
    @track versionDistribution = {};
    @track recentScans = [];
    @track currentScan = null;
    @track selectedScanId = null;
    @track findings = [];
    @track findingsSummary = {};
    @track changePlan = null;
    @track changeItems = [];

    @track isLoading = true;
    @track error = null;
    @track activeTab = 'dashboard';

    apiVersions = [];
    componentTypes = [];
    pollInterval = null;

    scopePolicyOptions = [
        { label: 'Custom Components Only', value: 'CustomOnly' },
        { label: 'Managed Packages Only', value: 'PackageOnly' },
        { label: 'All Components', value: 'All' }
    ];

    incrementPolicyOptions = [
        { label: 'Incremental Only (max 6 versions)', value: 'IncrementalOnly' },
        { label: 'Allow Large Jumps', value: 'AllowJumps' }
    ];

    deployOptionsList = [
        { label: 'Validate Only (do not deploy)', value: 'validateOnly' },
        { label: 'Enable Rollback Storage', value: 'enableRollback' }
    ];

    get orgTypeLabel() {
        return this.orgContext.isSandbox ? 'Sandbox' : 'Production';
    }

    get orgTypeBadgeClass() {
        return this.orgContext.isSandbox 
            ? 'slds-badge_lightest slds-m-right_small' 
            : 'slds-badge_inverse slds-m-right_small';
    }

    get apiVersionOptions() {
        return this.apiVersions.map(v => ({ label: `API ${v}`, value: v }));
    }

    get componentTypeOptions() {
        return this.componentTypes.map(t => ({ label: t, value: t }));
    }

    get hasFindings() {
        return this.findings && this.findings.length > 0;
    }

    get noFindings() {
        return !this.hasFindings;
    }

    get hasChangePlan() {
        return this.changePlan !== null;
    }

    get noChangePlan() {
        return !this.hasChangePlan;
    }

    get selectedDeployOptions() {
        const options = [];
        if (this.settings.validateOnlyDefault) options.push('validateOnly');
        if (this.settings.enableRollbackStorage) options.push('enableRollback');
        return options;
    }

    connectedCallback() {
        this.loadInitialData();
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    async loadInitialData() {
        this.isLoading = true;
        this.error = null;

        try {
            const [orgCtx, savedSettings, versions, types, counts, scans] = await Promise.all([
                getOrgContext(),
                getSettings(),
                getAvailableApiVersions(),
                getSupportedComponentTypes(),
                getInventoryCounts(),
                getRecentScans({ limitCount: 10 })
            ]);

            this.orgContext = orgCtx;
            this.settings = { ...this.settings, ...savedSettings };
            this.apiVersions = versions;
            this.componentTypes = types;
            this.inventoryCounts = counts;
            this.recentScans = scans;

            await this.loadVersionDistribution('ApexClass');

        } catch (err) {
            this.error = this.extractErrorMessage(err);
            console.error('Error loading data:', err);
        } finally {
            this.isLoading = false;
        }
    }

    async loadVersionDistribution(artifactType) {
        try {
            this.versionDistribution = await getVersionDistribution({ artifactType });
        } catch (err) {
            console.error('Error loading version distribution:', err);
        }
    }

    handleTabSelect(event) {
        this.activeTab = event.target.value;
    }

    handleRefresh() {
        this.loadInitialData();
    }

    handleInventoryRefresh() {
        this.loadInitialData();
    }

    handleSettingChange(event) {
        const field = event.target.name;
        let value = event.target.value;

        if (field === 'includedTypes') {
            value = event.detail.value;
        }

        this.settings = { ...this.settings, [field]: value };
    }

    handleDeployOptionsChange(event) {
        const selected = event.detail.value;
        this.settings = {
            ...this.settings,
            validateOnlyDefault: selected.includes('validateOnly'),
            enableRollbackStorage: selected.includes('enableRollback')
        };
    }

    async handleSaveSettings() {
        try {
            const result = await saveSettings({ settingsJson: JSON.stringify(this.settings) });
            this.settings = result;
            this.showToast('Success', 'Settings saved successfully', 'success');
        } catch (err) {
            this.showToast('Error', this.extractErrorMessage(err), 'error');
        }
    }

    async handleStartScan(event) {
        const scanRequest = event?.detail || {
            types: this.settings.includedTypes,
            namespacePolicy: this.settings.scopePolicy,
            targetApiVersion: this.settings.targetApiVersion,
            baselineMode: 'LastScan',
            includeContent: true
        };

        try {
            this.isLoading = true;
            const scanId = await startScan({ requestJson: JSON.stringify(scanRequest) });
            
            this.selectedScanId = scanId;
            this.currentScan = { id: scanId, status: 'Queued' };
            this.activeTab = 'scan';
            
            this.showToast('Scan Started', 'Scan has been queued for processing', 'success');
            this.startPolling(scanId);

        } catch (err) {
            this.showToast('Error', this.extractErrorMessage(err), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    startPolling(scanId) {
        this.stopPolling();
        
        this.pollInterval = setInterval(async () => {
            try {
                const status = await getScanStatus({ scanId });
                this.currentScan = status;

                if (status.status === 'Completed' || status.status === 'Failed' || status.status === 'Cancelled') {
                    this.stopPolling();
                    await this.loadScanResults(scanId);
                    
                    const scans = await getRecentScans({ limitCount: 10 });
                    this.recentScans = scans;

                    if (status.status === 'Completed') {
                        this.showToast('Scan Complete', `Found ${status.findingsCount} findings`, 'success');
                    } else if (status.status === 'Failed') {
                        this.showToast('Scan Failed', 'Check the scan details for errors', 'error');
                    }
                }
            } catch (err) {
                console.error('Polling error:', err);
                this.stopPolling();
            }
        }, 3000);
    }

    stopPolling() {
        if (this.pollInterval) {
            clearInterval(this.pollInterval);
            this.pollInterval = null;
        }
    }

    async loadScanResults(scanId) {
        try {
            const [findingsResult, summaryResult] = await Promise.all([
                getFindingsByScan({ scanId }),
                getFindingsSummary({ scanId })
            ]);

            this.findings = findingsResult;
            this.findingsSummary = summaryResult;

            if (this.findings.length > 0) {
                this.activeTab = 'findings';
            }
        } catch (err) {
            console.error('Error loading scan results:', err);
        }
    }

    async handleViewScan(event) {
        const scanId = event.detail.scanId;
        this.selectedScanId = scanId;
        await this.loadScanResults(scanId);
    }

    async handleCancelScan(event) {
        const scanId = event.detail.scanId;
        try {
            await cancelScan({ scanId });
            this.stopPolling();
            this.showToast('Scan Cancelled', 'The scan has been cancelled', 'info');
            
            const scans = await getRecentScans({ limitCount: 10 });
            this.recentScans = scans;
        } catch (err) {
            this.showToast('Error', this.extractErrorMessage(err), 'error');
        }
    }

    async handleCreatePlan(event) {
        const { scanId, targetApiVersion, incrementPolicy, validateOnly, testPolicy } = event.detail;

        try {
            this.isLoading = true;
            const planId = await createChangePlan({
                scanId,
                targetApiVersion: targetApiVersion || this.settings.targetApiVersion,
                incrementPolicy: incrementPolicy || this.settings.incrementPolicy,
                validateOnly: validateOnly !== undefined ? validateOnly : this.settings.validateOnlyDefault,
                testPolicy: testPolicy || 'RunSpecifiedTests'
            });

            const [plan, items] = await Promise.all([
                getChangePlan({ planId }),
                getChangeItems({ planId })
            ]);

            this.changePlan = plan;
            this.changeItems = items;
            this.activeTab = 'changeplan';

            this.showToast('Change Plan Created', 
                `Created plan with ${items.length} items (${plan.eligibleItems} eligible)`, 'success');

        } catch (err) {
            this.showToast('Error', this.extractErrorMessage(err), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleExecutePlan(event) {
        const planId = event.detail.planId;

        try {
            this.isLoading = true;
            const runId = await executePlan({ planId });
            
            this.showToast('Deployment Started', 'Deployment has been queued', 'success');

            const plan = await getChangePlan({ planId });
            this.changePlan = plan;

            const items = await getChangeItems({ planId });
            this.changeItems = items;

        } catch (err) {
            this.showToast('Error', this.extractErrorMessage(err), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractErrorMessage(error) {
        if (typeof error === 'string') return error;
        if (error.body?.message) return error.body.message;
        if (error.message) return error.message;
        return 'An unexpected error occurred';
    }
}
