import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import getBackupSummary from '@salesforce/apex/ApiVersionUpdaterController.getBackupSummary';
import getBackupItems from '@salesforce/apex/ApiVersionUpdaterController.getBackupItems';
import getBackupContent from '@salesforce/apex/ApiVersionUpdaterController.getBackupContent';
import createBackupForDeployment from '@salesforce/apex/ApiVersionUpdaterController.createBackupForDeployment';
import cleanupBackup from '@salesforce/apex/ApiVersionUpdaterController.cleanupBackup';
import restoreAll from '@salesforce/apex/ApiVersionUpdaterController.restoreAll';
import restoreItem from '@salesforce/apex/ApiVersionUpdaterController.restoreItem';
import getDiff from '@salesforce/apex/ApiVersionUpdaterController.getDiff';

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

export default class BackupRestorePanel extends LightningElement {
    @api deploymentRunId;
    @api hasBackup = false;
    
    @track backupSummary;
    @track backupItems = [];
    @track selectedItem;
    @track diffResult;
    @track previewContent;
    
    columns = COLUMNS;
    isLoading = false;
    showPreviewModal = false;
    showDiffModal = false;
    showRestoreConfirmModal = false;
    showCleanupConfirmModal = false;
    restoreAllMode = false;
    
    wiredSummaryResult;
    wiredItemsResult;
    
    @wire(getBackupSummary, { deploymentRunId: '$deploymentRunId' })
    wiredSummary(result) {
        this.wiredSummaryResult = result;
        if (result.data) {
            this.backupSummary = result.data;
        } else if (result.error) {
            this.handleError(result.error);
        }
    }
    
    @wire(getBackupItems, { deploymentRunId: '$deploymentRunId' })
    wiredItems(result) {
        this.wiredItemsResult = result;
        if (result.data) {
            this.backupItems = result.data;
        } else if (result.error) {
            this.handleError(result.error);
        }
    }
    
    get hasBackupData() {
        return this.backupSummary && this.backupSummary.backupCreatedAt;
    }
    
    get noBackupItems() {
        return !this.backupItems || this.backupItems.length === 0;
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
            if (this.restoreAllMode) {
                const results = await restoreAll({ deploymentRunId: this.deploymentRunId });
                const successCount = results.filter(r => r.success).length;
                const failCount = results.length - successCount;
                
                this.showToast(
                    'Restore Complete',
                    `Restored ${successCount} items${failCount > 0 ? `, ${failCount} failed` : ''}`,
                    failCount > 0 ? 'warning' : 'success'
                );
            } else {
                const result = await restoreItem({ backupItemId: this.selectedItem.id });
                
                if (result.success) {
                    this.showToast('Success', `${this.selectedItem.fullName} restored successfully`, 'success');
                } else {
                    this.showToast('Error', result.errorMessage, 'error');
                }
            }
            
            await this.refreshData();
            
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
        await Promise.all([
            refreshApex(this.wiredSummaryResult),
            refreshApex(this.wiredItemsResult)
        ]);
    }
    
    handleError(error) {
        console.error('BackupRestorePanel error:', error);
        const message = error?.body?.message || error?.message || 'An unknown error occurred';
        this.showToast('Error', message, 'error');
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
