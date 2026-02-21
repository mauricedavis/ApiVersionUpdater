import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getOrgContext from '@salesforce/apex/ApiVersionUpdaterController.getOrgContext';
import getSettings from '@salesforce/apex/ApiVersionUpdaterController.getSettings';
import saveSettings from '@salesforce/apex/ApiVersionUpdaterController.saveSettings';
import getAvailableApiVersions from '@salesforce/apex/ApiVersionUpdaterController.getAvailableApiVersions';
import getSupportedComponentTypes from '@salesforce/apex/ApiVersionUpdaterController.getSupportedComponentTypes';
import getInventoryCounts from '@salesforce/apex/ApiVersionUpdaterController.getInventoryCounts';
import getVersionDistribution from '@salesforce/apex/ApiVersionUpdaterController.getVersionDistribution';
import getComplianceMetrics from '@salesforce/apex/ApiVersionUpdaterController.getComplianceMetrics';
import getRecentScans from '@salesforce/apex/ApiVersionUpdaterController.getRecentScans';
import startScan from '@salesforce/apex/ApiVersionUpdaterController.startScan';
import getScanStatus from '@salesforce/apex/ApiVersionUpdaterController.getScanStatus';
import cancelScan from '@salesforce/apex/ApiVersionUpdaterController.cancelScan';
import getFindingsByScan from '@salesforce/apex/ApiVersionUpdaterController.getFindingsByScan';
import getFindingsSummary from '@salesforce/apex/ApiVersionUpdaterController.getFindingsSummary';
import createChangePlan from '@salesforce/apex/ApiVersionUpdaterController.createChangePlan';
import getChangePlan from '@salesforce/apex/ApiVersionUpdaterController.getChangePlan';
import getChangeItems from '@salesforce/apex/ApiVersionUpdaterController.getChangeItems';
import executePlanWithBackup from '@salesforce/apex/ApiVersionUpdaterController.executePlanWithBackup';
import getCurrentSession from '@salesforce/apex/ApiVersionUpdaterController.getCurrentSession';
import updateSessionScan from '@salesforce/apex/ApiVersionUpdaterController.updateSessionScan';
import updateSessionPlan from '@salesforce/apex/ApiVersionUpdaterController.updateSessionPlan';
import updateSessionDeploymentRun from '@salesforce/apex/ApiVersionUpdaterController.updateSessionDeploymentRun';
import clearSession from '@salesforce/apex/ApiVersionUpdaterController.clearSession';

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
    @track complianceMetrics = null;
    @track recentScans = [];
    @track currentScan = null;
    @track selectedScanId = null;
    @track findings = [];
    @track findingsSummary = {};
    @track changePlan = null;
    @track changeItems = [];
    @track currentDeploymentRunId = null;
    @track hasBackup = false;
    
    @track session = null;
    @track workflowStep = 0;
    @track completedSteps = [];

    @track isLoading = true;
    @track error = null;
    @track activeTab = 'dashboard';
    @track activeScanSubTab = 'current';

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

    get currentPlanId() {
        return this.changePlan?.id || this.session?.currentChangePlanId || null;
    }
    
    get hasScan() {
        return this.currentScan !== null || this.selectedScanId !== null;
    }

    get isScanRunning() {
        return this.currentScan?.status === 'Running' || this.currentScan?.status === 'Queued';
    }

    get hasScanResults() {
        return this.hasScan && 
            (this.currentScan?.status === 'Completed' || this.currentScan?.status === 'Failed') &&
            this.findings !== null;
    }

    get showScanStatus() {
        return this.isScanRunning || (this.hasScan && this.recentScans?.length > 0);
    }

    get showScanEmptyState() {
        return !this.hasScan && !this.isScanRunning;
    }

    get hasRecentScans() {
        return this.recentScans && this.recentScans.length > 0;
    }

    get recentScansData() {
        if (!this.recentScans) return [];
        return this.recentScans.map(scan => ({
            scanId: scan.scanId || scan.id,
            name: scan.name || `Scan ${scan.scanId || scan.id}`,
            status: scan.status,
            startedAt: scan.startedAt,
            findingsCount: scan.findingsCount || 0,
            alertsCount: scan.alertsCount || 0,
            targetApiVersion: scan.targetApiVersion
        }));
    }

    get scanHistoryColumns() {
        return [
            { label: 'Scan', fieldName: 'name', type: 'text' },
            { label: 'Status', fieldName: 'status', type: 'text' },
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
            { label: 'Findings', fieldName: 'findingsCount', type: 'number' },
            { label: 'Alerts', fieldName: 'alertsCount', type: 'number', cellAttributes: { class: 'slds-text-color_error' } },
            { label: 'Target API', fieldName: 'targetApiVersion', type: 'text' },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [
                        { label: 'View Findings', name: 'view' }
                    ]
                }
            }
        ];
    }

    get scanStatusBadgeClass() {
        const status = this.currentScan?.status;
        if (status === 'Completed') return 'slds-badge_success';
        if (status === 'Running' || status === 'Queued') return 'slds-badge_warning';
        if (status === 'Failed') return 'slds-badge_error';
        return '';
    }

    get scanTabBadge() {
        if (!this.hasScan) return '';
        if (this.currentScan?.status === 'Running') return 'In Progress';
        if (this.currentScan?.status === 'Completed') return 'Ready';
        return '';
    }

    get findingsTabBadge() {
        if (!this.hasFindings) return 'No Findings';
        return `${this.findings.length} findings`;
    }

    get findingsTabDisabled() {
        return !this.hasScan || (this.currentScan?.status !== 'Completed' && this.currentScan?.status !== 'Failed');
    }

    get planTabBadge() {
        if (!this.hasChangePlan) return 'No Plan';
        return this.changePlan.status || '';
    }

    get planTabDisabled() {
        return !this.hasChangePlan;
    }

    get backupTabBadge() {
        if (!this.currentDeploymentRunId) return 'No Deployment';
        if (this.hasBackup) return 'Backup Available';
        return '';
    }

    get backupTabDisabled() {
        return !this.currentDeploymentRunId;
    }

    get currentScanName() {
        return this.currentScan?.name || '';
    }

    get currentScanStatus() {
        return this.currentScan?.status || '';
    }

    get currentScanStartedAt() {
        return this.currentScan?.startedAt || null;
    }

    get findingsCount() {
        return this.currentScan?.findingsCount || this.findings?.length || 0;
    }

    get alertsCount() {
        return this.currentScan?.alertsCount || 0;
    }

    get componentsNeedingUpgrade() {
        return this.complianceMetrics?.nonCompliantComponents || 0;
    }

    get currentPlanName() {
        return this.changePlan?.name || '';
    }

    get currentPlanStatus() {
        return this.changePlan?.status || '';
    }

    get changeItemsCount() {
        return this.changeItems?.length || 0;
    }

    get currentDeploymentStatus() {
        return this.session?.currentDeploymentRunStatus || '';
    }

    get noChangePlan() {
        return !this.hasChangePlan;
    }

    get hasDeploymentRun() {
        return this.currentDeploymentRunId !== null;
    }

    get noDeploymentRun() {
        return !this.hasDeploymentRun;
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
            console.log('Starting loadInitialData...');
            
            const [orgCtx, savedSettings, versions, types, counts, scans, sessionData] = await Promise.all([
                getOrgContext(),
                getSettings(),
                getAvailableApiVersions(),
                getSupportedComponentTypes(),
                getInventoryCounts(),
                getRecentScans({ limitCount: 10 }),
                getCurrentSession()
            ]);

            console.log('Initial data loaded:', { orgCtx, savedSettings, counts, sessionData });

            this.orgContext = orgCtx;
            this.settings = { ...this.settings, ...savedSettings };
            this.apiVersions = versions;
            this.componentTypes = types;
            this.inventoryCounts = counts;
            this.recentScans = scans;
            this.session = sessionData;

            console.log('Settings after merge:', this.settings);
            console.log('Session restored:', this.session);

            await this.loadVersionDistribution('ApexClass');
            await this.loadComplianceMetrics();
            
            await this.restoreSessionState();

        } catch (err) {
            this.error = this.extractErrorMessage(err);
            console.error('Error loading data:', err);
        } finally {
            this.isLoading = false;
        }
    }
    
    async restoreSessionState() {
        if (!this.session) return;
        
        this.workflowStep = this.session.workflowStep || 0;
        this.updateCompletedSteps();
        
        if (this.session.currentScanId) {
            this.selectedScanId = this.session.currentScanId;
            try {
                const scanStatus = await getScanStatus({ scanId: this.session.currentScanId });
                if (scanStatus) {
                    this.currentScan = scanStatus;
                    
                    if (scanStatus.status === 'Completed' || scanStatus.status === 'Failed') {
                        const [findingsData, summary] = await Promise.all([
                            getFindingsByScan({ scanId: this.session.currentScanId }),
                            getFindingsSummary({ scanId: this.session.currentScanId })
                        ]);
                        this.findings = findingsData;
                        this.findingsSummary = summary;
                    }
                } else {
                    this.selectedScanId = null;
                    console.log('Scan no longer exists, clearing reference');
                }
            } catch (e) {
                console.log('Could not restore scan state:', e);
                this.selectedScanId = null;
            }
        }
        
        if (this.session.currentChangePlanId) {
            try {
                const [plan, items] = await Promise.all([
                    getChangePlan({ planId: this.session.currentChangePlanId }),
                    getChangeItems({ planId: this.session.currentChangePlanId })
                ]);
                this.changePlan = plan;
                this.changeItems = items;
            } catch (e) {
                console.log('Could not restore plan state:', e);
            }
        }
        
        if (this.session.currentDeploymentRunId) {
            this.currentDeploymentRunId = this.session.currentDeploymentRunId;
            this.hasBackup = true;
        }
    }
    
    updateCompletedSteps() {
        const completed = [];
        if (this.workflowStep >= 2) completed.push(1);
        if (this.workflowStep >= 3) completed.push(2);
        if (this.workflowStep >= 4) completed.push(3);
        if (this.workflowStep >= 5) completed.push(4);
        this.completedSteps = completed;
    }
    
    async loadComplianceMetrics() {
        try {
            const targetVersionStr = this.settings.targetApiVersion || '65.0';
            const targetVersion = parseFloat(targetVersionStr);
            const scopePolicy = this.settings.scopePolicy || 'CustomOnly';
            
            console.log('Loading compliance metrics with target:', targetVersion, 'scope:', scopePolicy);
            
            this.complianceMetrics = await getComplianceMetrics({ 
                targetApiVersion: targetVersion,
                scopePolicy: scopePolicy 
            });
            
            console.log('Compliance metrics loaded:', this.complianceMetrics);
        } catch (err) {
            const errorMsg = err?.body?.message || err?.message || JSON.stringify(err);
            console.error('Error loading compliance metrics:', errorMsg);
            this.showToast('Compliance Metrics Error', errorMsg, 'error');
            this.complianceMetrics = null;
        }
    }

    async loadVersionDistribution(artifactType) {
        try {
            console.log('Loading version distribution for:', artifactType);
            const distribution = await getVersionDistribution({ artifactType });
            console.log('Version distribution loaded:', distribution);
            this.versionDistribution = distribution;
        } catch (err) {
            const errorMsg = err?.body?.message || err?.message || JSON.stringify(err);
            console.error('Error loading version distribution:', errorMsg);
            this.showToast('Version Distribution Error', errorMsg, 'error');
            this.versionDistribution = {};
        }
    }

    handleTabSelect(event) {
        this.activeTab = event.target.value;
        
        if (this.activeTab === 'backup') {
            setTimeout(() => {
                const backupPanel = this.template.querySelector('c-backup-restore-panel');
                if (backupPanel) {
                    backupPanel.refresh();
                }
            }, 100);
        }
    }

    handleRefresh() {
        this.loadInitialData();
    }

    async handleInventoryRefresh() {
        this.isLoading = true;
        try {
            const counts = await getInventoryCounts();
            this.inventoryCounts = counts;
            
            await Promise.all([
                this.loadVersionDistribution('ApexClass'),
                this.loadComplianceMetrics()
            ]);
        } catch (err) {
            this.showToast('Error', this.extractErrorMessage(err), 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    async handleTypeChange(event) {
        const type = event.detail.type;
        await this.loadVersionDistribution(type);
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
            
            await this.loadComplianceMetrics();
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
            this.activeTab = 'scanfindings';
            this.workflowStep = 1;
            this.updateCompletedSteps();
            
            this.session = await updateSessionScan({ scanId });
            
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
                if (!status) {
                    console.error('Scan not found during polling');
                    this.stopPolling();
                    return;
                }
                this.currentScan = status;

                if (status.status === 'Completed' || status.status === 'Failed' || status.status === 'Cancelled') {
                    this.stopPolling();
                    await this.loadScanResults(scanId);
                    
                    const scans = await getRecentScans({ limitCount: 10 });
                    this.recentScans = scans;

                    if (status.status === 'Completed') {
                        this.workflowStep = 2;
                        this.updateCompletedSteps();
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
                this.activeTab = 'scanfindings';
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

        console.log('handleCreatePlan called with:', { scanId, targetApiVersion, incrementPolicy });

        if (!scanId) {
            this.showToast('Error', 'No scan selected. Please run a compliance scan first.', 'error');
            return;
        }

        try {
            this.isLoading = true;
            
            console.log('Calling createChangePlan with:', {
                scanId,
                targetApiVersion: targetApiVersion || this.settings.targetApiVersion,
                incrementPolicy: incrementPolicy || this.settings.incrementPolicy,
                validateOnly: validateOnly !== undefined ? validateOnly : this.settings.validateOnlyDefault,
                testPolicy: testPolicy || 'RunSpecifiedTests'
            });

            const planId = await createChangePlan({
                scanId,
                targetApiVersion: targetApiVersion || this.settings.targetApiVersion,
                incrementPolicy: incrementPolicy || this.settings.incrementPolicy,
                validateOnly: validateOnly !== undefined ? validateOnly : this.settings.validateOnlyDefault,
                testPolicy: testPolicy || 'RunSpecifiedTests'
            });

            console.log('Change plan created with ID:', planId);

            const [plan, items] = await Promise.all([
                getChangePlan({ planId }),
                getChangeItems({ planId })
            ]);

            this.changePlan = plan;
            this.changeItems = items;
            this.activeTab = 'changeplan';
            this.workflowStep = 3;
            this.updateCompletedSteps();
            
            this.session = await updateSessionPlan({ planId });

            this.showToast('Change Plan Created', 
                `Created plan with ${items.length} items (${plan.eligibleItems} eligible)`, 'success');

        } catch (err) {
            console.error('Error creating change plan:', err);
            const errorMessage = this.extractErrorMessage(err);
            console.error('Extracted error message:', errorMessage);
            this.showToast('Error Creating Change Plan', errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleExecutePlan(event) {
        const { planId, createBackup, navigateToBackup, selectedIds } = event.detail;
        
        console.log('handleExecutePlan called with:', {
            planId,
            createBackup,
            navigateToBackup,
            selectedIds,
            selectedIdsLength: selectedIds ? selectedIds.length : 0
        });

        if (createBackup && (!selectedIds || selectedIds.length === 0)) {
            this.showToast('Error', 'No items selected for backup. Please select and validate items first.', 'error');
            return;
        }

        try {
            this.isLoading = true;
            const runId = await executePlanWithBackup({ 
                planId, 
                createBackup: createBackup || false,
                selectedItemIds: selectedIds || []
            });
            
            console.log('executePlanWithBackup returned runId:', runId);
            
            this.currentDeploymentRunId = runId;
            this.hasBackup = createBackup;
            this.workflowStep = 4;
            this.updateCompletedSteps();
            
            this.session = await updateSessionDeploymentRun({ deploymentRunId: runId });
            
            this.showToast('Deployment Started', 'Deployment has been queued', 'success');

            const plan = await getChangePlan({ planId });
            this.changePlan = plan;

            const items = await getChangeItems({ planId });
            this.changeItems = items;

            const changePlanPanel = this.template.querySelector('c-change-plan-panel');
            if (changePlanPanel) {
                changePlanPanel.deploymentComplete();
            }

            if (navigateToBackup && createBackup) {
                setTimeout(() => {
                    this.activeTab = 'backup';
                    this.showToast('Backup Created', 
                        'Deployment complete. Backup created for restore if needed.', 
                        'success');
                    
                    setTimeout(() => {
                        const backupPanel = this.template.querySelector('c-backup-restore-panel');
                        if (backupPanel) {
                            backupPanel.refresh();
                        }
                    }, 100);
                }, 1500);
            } else {
                this.showToast('Deployment Complete', 
                    `Successfully processed ${items.filter(i => i.applyStatus === 'Applied').length} components`, 
                    'success');
            }

        } catch (err) {
            this.showToast('Error', this.extractErrorMessage(err), 'error');
            
            const changePlanPanel = this.template.querySelector('c-change-plan-panel');
            if (changePlanPanel) {
                changePlanPanel.deploymentComplete();
            }
        } finally {
            this.isLoading = false;
        }
    }

    handleBackupCleanedUp() {
        this.hasBackup = false;
        this.showToast('Success', 'Backup has been cleaned up', 'success');
    }

    async handlePlanReset(event) {
        const { planId } = event.detail;
        try {
            this.isLoading = true;
            
            const plan = await getChangePlan({ planId });
            this.changePlan = plan;
            
            const items = await getChangeItems({ planId });
            this.changeItems = items;
            
            this.currentDeploymentRunId = null;
            
            this.showToast('Plan Reset', 'Plan has been reset. You can now re-validate and deploy.', 'success');
        } catch (err) {
            this.showToast('Error', this.extractErrorMessage(err), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleShowError(event) {
        const message = event.detail?.message || 'An error occurred';
        this.showToast('Error', message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractErrorMessage(error) {
        console.log('Full error object:', JSON.stringify(error, null, 2));
        
        if (typeof error === 'string') return error;
        if (error.body?.message) return error.body.message;
        if (error.body?.error) return error.body.error;
        if (error.body?.pageErrors && error.body.pageErrors.length > 0) {
            return error.body.pageErrors[0].message;
        }
        if (error.body?.fieldErrors) {
            const fieldNames = Object.keys(error.body.fieldErrors);
            if (fieldNames.length > 0) {
                return error.body.fieldErrors[fieldNames[0]][0].message;
            }
        }
        if (error.message) return error.message;
        if (error.statusText) return error.statusText;
        return 'An unexpected error occurred. Check the browser console for details.';
    }

    async handleClearSession() {
        try {
            await clearSession();
            
            this.session = null;
            this.workflowStep = 0;
            this.completedSteps = [];
            this.currentScan = null;
            this.selectedScanId = null;
            this.findings = [];
            this.findingsSummary = {};
            this.changePlan = null;
            this.changeItems = [];
            this.currentDeploymentRunId = null;
            this.hasBackup = false;
            this.activeTab = 'dashboard';
            
            this.showToast('Session Cleared', 'Starting a new session', 'info');
        } catch (err) {
            this.showToast('Error', this.extractErrorMessage(err), 'error');
        }
    }

    handleStepClick(event) {
        const { stepId, stepLabel } = event.detail;
        
        const stepToTab = {
            1: 'scanfindings',
            2: 'scanfindings',
            3: 'changeplan',
            4: 'changeplan',
            5: 'backup'
        };
        
        const targetTab = stepToTab[stepId];
        if (targetTab) {
            this.activeTab = targetTab;
        }
    }

    async handleScanHistoryAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        
        if (action.name === 'view') {
            try {
                this.isLoading = true;
                this.selectedScanId = row.scanId;
                
                const scanStatus = await getScanStatus({ scanId: row.scanId });
                if (!scanStatus) {
                    this.showToast('Error', 'Scan not found', 'error');
                    this.selectedScanId = null;
                    return;
                }
                this.currentScan = scanStatus;
                
                if (scanStatus.status === 'Completed' || scanStatus.status === 'Failed') {
                    await this.loadScanResults(row.scanId);
                    this.workflowStep = 2;
                } else {
                    this.workflowStep = 1;
                }
                this.updateCompletedSteps();
                
                this.activeScanSubTab = 'current';
                this.showToast('Scan Loaded', `Viewing findings for: ${row.name}`, 'success');
                
            } catch (err) {
                this.showToast('Error', this.extractErrorMessage(err), 'error');
            } finally {
                this.isLoading = false;
            }
        }
    }

    async handleScanSelect(event) {
        const id = event.detail.id || event.detail.scanId;
        
        if (!id) {
            this.activeTab = 'scanfindings';
            return;
        }
        
        try {
            this.isLoading = true;
            this.selectedScanId = id;
            
            const scanStatus = await getScanStatus({ scanId: id });
            if (!scanStatus) {
                this.showToast('Error', 'Scan not found', 'error');
                this.selectedScanId = null;
                return;
            }
            this.currentScan = scanStatus;
            
            this.session = await updateSessionScan({ scanId: id });
            
            if (scanStatus.status === 'Completed' || scanStatus.status === 'Failed') {
                await this.loadScanResults(id);
                this.workflowStep = 2;
            } else {
                this.workflowStep = 1;
            }
            this.updateCompletedSteps();
            
            this.changePlan = null;
            this.changeItems = [];
            this.currentDeploymentRunId = null;
            this.hasBackup = false;
            
            this.activeTab = 'scanfindings';
            this.showToast('Scan Loaded', `Loaded scan: ${scanStatus.name || id}`, 'success');
            
        } catch (err) {
            this.showToast('Error', this.extractErrorMessage(err), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handlePlanSelect(event) {
        const id = event.detail.id || event.detail.planId;
        
        if (!id) {
            this.activeTab = 'changeplan';
            return;
        }
        
        try {
            this.isLoading = true;
            
            const [plan, items] = await Promise.all([
                getChangePlan({ planId: id }),
                getChangeItems({ planId: id })
            ]);
            
            this.changePlan = plan;
            this.changeItems = items;
            
            this.session = await updateSessionPlan({ planId: id });
            this.workflowStep = 3;
            this.updateCompletedSteps();
            
            this.activeTab = 'changeplan';
            this.showToast('Plan Loaded', `Loaded plan: ${plan.name || id}`, 'success');
            
        } catch (err) {
            this.showToast('Error', this.extractErrorMessage(err), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleViewDeployment() {
        this.activeTab = 'backup';
    }
}
