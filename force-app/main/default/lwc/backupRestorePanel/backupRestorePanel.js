import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import getBackupSummary from '@salesforce/apex/ApiVersionUpdaterController.getBackupSummary';
import getBackupItems from '@salesforce/apex/ApiVersionUpdaterController.getBackupItems';
import getBackupSummaryByPlan from '@salesforce/apex/ApiVersionUpdaterController.getBackupSummaryByPlan';
import getBackupItemsByPlan from '@salesforce/apex/ApiVersionUpdaterController.getBackupItemsByPlan';
import getBackupContent from '@salesforce/apex/ApiVersionUpdaterController.getBackupContent';
import createBackupForDeployment from '@salesforce/apex/ApiVersionUpdaterController.createBackupForDeployment';
import cleanupBackup from '@salesforce/apex/ApiVersionUpdaterController.cleanupBackup';
import restoreAll from '@salesforce/apex/ApiVersionUpdaterController.restoreAll';
import restoreItem from '@salesforce/apex/ApiVersionUpdaterController.restoreItem';
import getDiff from '@salesforce/apex/ApiVersionUpdaterController.getDiff';
import getDeploymentHistory from '@salesforce/apex/ApiVersionUpdaterController.getDeploymentHistory';
import getManualRestoreData from '@salesforce/apex/ApiVersionUpdaterController.getManualRestoreData';
import verifyAndMarkRestored from '@salesforce/apex/ApiVersionUpdaterController.verifyAndMarkRestored';
import markAsRestoredManually from '@salesforce/apex/ApiVersionUpdaterController.markAsRestoredManually';

const COLUMNS = [
    { label: 'Name', fieldName: 'fullName', type: 'text', sortable: true },
    { label: 'Type', fieldName: 'artifactType', type: 'text', sortable: true },
    { label: 'API Version', fieldName: 'originalApiVersion', type: 'number', sortable: true },
    { label: 'Status', fieldName: 'restoreStatus', type: 'text', sortable: true },
    { label: 'Backed Up', fieldName: 'backupCreatedAt', type: 'date', 
        typeAttributes: { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }
    },
    { label: 'Restored At', fieldName: 'restoredAt', type: 'date',
        typeAttributes: { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }
    },
    {
        type: 'action',
        typeAttributes: { rowActions: [
            { label: 'Preview', name: 'preview' },
            { label: 'View Diff', name: 'diff' },
            { label: 'Restore', name: 'restore' }
        ]}
    }
];

const DEPLOYMENT_HISTORY_COLUMNS = [
    { label: 'Component Name', fieldName: 'fullName', type: 'text', sortable: true },
    { label: 'Type', fieldName: 'artifactType', type: 'text', sortable: true, initialWidth: 120 },
    { label: 'From Version', fieldName: 'fromVersion', type: 'number', sortable: true, initialWidth: 110,
        typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 }
    },
    { label: 'To Version', fieldName: 'toVersion', type: 'number', sortable: true, initialWidth: 110,
        typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 }
    },
    { label: 'Status', fieldName: 'status', type: 'text', sortable: true, initialWidth: 100 },
    { label: 'Deployed At', fieldName: 'deployedAt', type: 'date', sortable: true,
        typeAttributes: { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }
    }
];

export default class BackupRestorePanel extends LightningElement {
    @api deploymentRunId;
    @api planId;
    @api hasBackup = false;
    
    @track backupSummary;
    @track backupItems = [];
    @track deploymentHistoryItems = [];
    @track selectedItem;
    @track diffResult;
    @track previewContent;
    @track activeSubTab = 'history';
    @track showDeploymentSuccess = false;
    @track deploymentSuccessMessage = '';
    
    columns = COLUMNS;
    deploymentHistoryColumns = DEPLOYMENT_HISTORY_COLUMNS;
    isLoading = false;
    showPreviewModal = false;
    showDiffModal = false;
    showRestoreConfirmModal = false;
    showCleanupConfirmModal = false;
    showManualRestoreModal = false;
    restoreAllMode = false;
    deploymentHistoryLoaded = false;
    
    @track manualRestoreData;
    codeCopied = false;
    
    wiredSummaryResult;
    wiredItemsResult;
    backupItemsLoaded = false;
    
    connectedCallback() {
        if (this.planId) {
            this.loadDeploymentHistory();
            this.loadBackupItemsByPlan();
        }
    }
    
    async loadBackupItemsByPlan() {
        if (!this.planId || this.backupItemsLoaded) return;
        
        this.isLoading = true;
        try {
            const [summary, items] = await Promise.all([
                getBackupSummaryByPlan({ planId: this.planId }),
                getBackupItemsByPlan({ planId: this.planId })
            ]);
            this.backupSummary = summary;
            this.backupItems = items || [];
            this.backupItemsLoaded = true;
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }
    
    get hasBackupData() {
        return this.backupSummary && this.backupSummary.backupCreatedAt;
    }
    
    get noBackupItems() {
        return !this.backupItems || this.backupItems.length === 0;
    }
    
    get copyButtonLabel() {
        return this.codeCopied ? 'Code Copied!' : 'Copy Code';
    }
    
    get expirationDateFormatted() {
        if (!this.backupSummary || !this.backupSummary.expirationDate) return '';
        const date = new Date(this.backupSummary.expirationDate);
        return date.toLocaleDateString();
    }
    
    get backupCreatedFormatted() {
        if (!this.backupSummary || !this.backupSummary.backupCreatedAt) return '';
        const date = new Date(this.backupSummary.backupCreatedAt);
        return date.toLocaleString();
    }
    
    get daysUntilExpiration() {
        if (!this.backupSummary || !this.backupSummary.expirationDate) return 0;
        const exp = new Date(this.backupSummary.expirationDate);
        const today = new Date();
        const diffTime = exp - today;
        return Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    }
    
    get expirationWarningClass() {
        const days = this.daysUntilExpiration;
        if (days <= 7) return 'slds-text-color_error';
        if (days <= 30) return 'slds-text-color_warning';
        return '';
    }
    
    get restorableItemCount() {
        return this.backupItems.filter(item => item.restoreStatus === 'NotRestored').length;
    }
    
    get hasRestorableItems() {
        return this.restorableItemCount > 0;
    }
    
    get diffHasChanges() {
        return this.diffResult && (this.diffResult.hasContentChanges || this.diffResult.hasMetadataChanges);
    }
    
    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        
        switch (action.name) {
            case 'preview':
                this.handlePreview(row);
                break;
            case 'diff':
                this.handleViewDiff(row);
                break;
            case 'restore':
                this.handleRestoreSingle(row);
                break;
        }
    }
    
    async handlePreview(row) {
        this.isLoading = true;
        this.selectedItem = row;
        
        try {
            this.previewContent = await getBackupContent({ backupItemId: row.id });
            this.showPreviewModal = true;
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }
    
    async handleViewDiff(row) {
        this.isLoading = true;
        this.selectedItem = row;
        
        try {
            this.diffResult = await getDiff({ backupItemId: row.id });
            this.showDiffModal = true;
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }
    
    handleRestoreSingle(row) {
        this.selectedItem = row;
        this.restoreAllMode = false;
        this.showRestoreConfirmModal = true;
    }
    
    handleRestoreAllClick() {
        this.restoreAllMode = true;
        this.showRestoreConfirmModal = true;
    }
    
    closePreviewModal() {
        this.showPreviewModal = false;
        this.previewContent = null;
    }
    
    closeDiffModal() {
        this.showDiffModal = false;
        this.diffResult = null;
    }
    
    closeRestoreConfirmModal() {
        this.showRestoreConfirmModal = false;
    }
    
    closeCleanupConfirmModal() {
        this.showCleanupConfirmModal = false;
    }
    
    async confirmRestore() {
        this.isLoading = true;
        this.showRestoreConfirmModal = false;
        
        try {
            console.log('Starting restore for:', this.selectedItem);
            
            if (this.restoreAllMode) {
                this.showToast('Manual Restore Required', 
                    'Due to session limitations, please restore items individually using the manual restore option.', 
                    'warning');
                return;
            }
            
            const data = await getManualRestoreData({ backupItemId: this.selectedItem.id });
            console.log('Manual restore data:', data);
            
            if (!data.success) {
                this.showToast('Error', data.errorMessage || 'Failed to get restore data', 'error');
                return;
            }
            
            this.manualRestoreData = data;
            this.codeCopied = false;
            this.showManualRestoreModal = true;
            
        } catch (error) {
            console.error('Restore exception:', error);
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }
    
    closeManualRestoreModal() {
        this.showManualRestoreModal = false;
        this.manualRestoreData = null;
        this.codeCopied = false;
    }
    
    handleCopyRestoreCode() {
        try {
            const textArea = document.createElement('textarea');
            textArea.value = this.manualRestoreData.backupContent;
            textArea.style.position = 'fixed';
            textArea.style.left = '-9999px';
            textArea.style.top = '0';
            document.body.appendChild(textArea);
            textArea.focus();
            textArea.select();
            
            const successful = document.execCommand('copy');
            document.body.removeChild(textArea);
            
            if (successful) {
                this.codeCopied = true;
                this.showToast('Copied', 'Code copied to clipboard', 'success');
            } else {
                this.showToast('Copy Failed', 'Please manually select and copy the code from the preview below', 'warning');
            }
        } catch (error) {
            console.error('Copy failed:', error);
            this.showToast('Copy Failed', 'Please manually select and copy the code from the preview below', 'warning');
        }
    }
    
    handleOpenRestoreInSetup() {
        if (this.manualRestoreData && this.manualRestoreData.setupUrl) {
            window.open(this.manualRestoreData.setupUrl, '_blank');
        }
    }
    
    async handleVerifyRestore() {
        this.isLoading = true;
        try {
            const result = await verifyAndMarkRestored({ backupItemId: this.manualRestoreData.backupItemId });
            
            if (result.verified && result.markedRestored) {
                this.showToast('Restore Verified', result.message, 'success');
                this.closeManualRestoreModal();
                await this.refreshData();
            } else {
                this.showToast('Verification Failed', result.message, 'warning');
            }
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }
    
    async handleMarkRestoredManually() {
        this.isLoading = true;
        try {
            const result = await markAsRestoredManually({ backupItemId: this.manualRestoreData.backupItemId });
            
            if (result.markedRestored) {
                this.showToast('Marked as Restored', result.message, 'success');
                this.closeManualRestoreModal();
                await this.refreshData();
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }
    
    handleCleanupClick() {
        this.showCleanupConfirmModal = true;
    }
    
    async confirmCleanup() {
        this.isLoading = true;
        this.showCleanupConfirmModal = false;
        
        try {
            await cleanupBackup({ deploymentRunId: this.deploymentRunId });
            this.showToast('Success', 'Backup cleaned up successfully', 'success');
            await this.refreshData();
            
            this.dispatchEvent(new CustomEvent('backupcleanedup'));
            
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }
    
    async handleCreateBackup() {
        this.isLoading = true;
        
        try {
            await createBackupForDeployment({ deploymentRunId: this.deploymentRunId });
            this.showToast('Success', 'Backup created successfully', 'success');
            await this.refreshData();
            
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }
    
    async refreshData() {
        this.backupItemsLoaded = false;
        await this.loadBackupItemsByPlan();
    }

    @api
    async refresh() {
        await this.refreshData();
    }
    
    @api
    showBackupTab() {
        this.activeSubTab = 'backup';
        if (!this.backupItemsLoaded) {
            this.loadBackupItemsByPlan();
        }
    }
    
    @api
    async deploymentComplete(successCount, failCount) {
        this.activeSubTab = 'history';
        this.deploymentHistoryLoaded = false;
        this.backupItemsLoaded = false;
        
        await Promise.all([
            this.loadDeploymentHistory(),
            this.loadBackupItemsByPlan()
        ]);
        
        if (failCount === 0 && successCount > 0) {
            this.showDeploymentSuccess = true;
            this.deploymentSuccessMessage = `${successCount} component(s) updated successfully.`;
            setTimeout(() => {
                this.showDeploymentSuccess = false;
            }, 10000);
        }
    }

    get hasDeploymentHistory() {
        return this.deploymentHistoryItems && this.deploymentHistoryItems.length > 0;
    }

    handleSubTabChange(event) {
        this.activeSubTab = event.target.value;
        if (this.activeSubTab === 'history' && !this.deploymentHistoryLoaded) {
            this.loadDeploymentHistory();
        }
        if (this.activeSubTab === 'backup' && !this.backupItemsLoaded) {
            this.loadBackupItemsByPlan();
        }
    }

    async loadDeploymentHistory() {
        if (!this.planId) return;
        
        this.isLoading = true;
        try {
            const history = await getDeploymentHistory({ planId: this.planId });
            this.deploymentHistoryItems = history;
            this.deploymentHistoryLoaded = true;
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }
    
    handleError(error) {
        console.error('BackupRestorePanel error:', JSON.stringify(error));
        let message = 'An unknown error occurred';
        
        if (error?.body?.message) {
            message = error.body.message;
        } else if (error?.message) {
            message = error.message;
        } else if (error?.body?.fieldErrors) {
            const fieldErrors = Object.values(error.body.fieldErrors).flat();
            message = fieldErrors.map(e => e.message).join(', ');
        } else if (error?.body?.pageErrors) {
            message = error.body.pageErrors.map(e => e.message).join(', ');
        } else if (typeof error === 'string') {
            message = error;
        } else if (error?.body) {
            message = JSON.stringify(error.body);
        }
        
        this.showToast('Error', message, 'error');
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
