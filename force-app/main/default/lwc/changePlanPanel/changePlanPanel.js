import { LightningElement, api, track } from 'lwc';
import getDeploymentRunDetails from '@salesforce/apex/ApiVersionUpdaterController.getDeploymentRunDetails';
import getDeploymentErrorsForPlan from '@salesforce/apex/ApiVersionUpdaterController.getDeploymentErrorsForPlan';
import resetPlanForRetry from '@salesforce/apex/ApiVersionUpdaterController.resetPlanForRetry';

export default class ChangePlanPanel extends LightningElement {
    @api changePlan = {};
    @api changeItems = [];
    @api deploymentRunId;

    @track eligibilityFilter = 'all';
    @track sortedBy = 'unitNumber';
    @track sortedDirection = 'asc';
    @track selectedItemIds = [];
    @track isValidating = false;
    @track isDeploying = false;
    @track validationComplete = false;
    @track validationResults = null;
    @track createBackupBeforeDeploy = true;
    @track showDeployConfirmation = false;
    @track deploymentError = null;
    _errorLoadAttempted = false;

    eligibilityOptions = [
        { label: 'All Items', value: 'all' },
        { label: 'Eligible Only', value: 'Eligible' },
        { label: 'Blocked Only', value: 'Blocked' },
        { label: 'Failed Only', value: 'Failed' }
    ];

    columns = [
        { 
            label: '#', 
            fieldName: 'unitNumber', 
            type: 'number',
            sortable: true,
            initialWidth: 60
        },
        { 
            label: 'Component', 
            fieldName: 'fullName', 
            type: 'text',
            sortable: true
        },
        { 
            label: 'Type', 
            fieldName: 'artifactType', 
            type: 'text',
            sortable: true,
            initialWidth: 120
        },
        { 
            label: 'Current', 
            fieldName: 'currentApiVersion', 
            type: 'number',
            sortable: true,
            initialWidth: 90,
            typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 }
        },
        { 
            label: 'Target', 
            fieldName: 'targetApiVersion', 
            type: 'number',
            sortable: true,
            initialWidth: 90,
            typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 }
        },
        { 
            label: 'Eligibility', 
            fieldName: 'eligibility', 
            type: 'text',
            sortable: true,
            initialWidth: 100,
            cellAttributes: { class: { fieldName: 'eligibilityClass' } }
        },
        { 
            label: 'Validation', 
            fieldName: 'validationStatus', 
            type: 'text',
            sortable: true,
            initialWidth: 110,
            cellAttributes: { 
                class: { fieldName: 'validationClass' },
                iconName: { fieldName: 'validationIcon' },
                iconPosition: 'left'
            }
        },
        { 
            label: 'Status', 
            fieldName: 'applyStatus', 
            type: 'text',
            sortable: true,
            initialWidth: 100,
            cellAttributes: { class: { fieldName: 'applyStatusClass' } }
        },
        { 
            label: 'Notes', 
            fieldName: 'displayNotes', 
            type: 'text',
            wrapText: true
        }
    ];

    get planStatusClass() {
        const statusMap = {
            'Draft': 'status-badge status-draft',
            'Ready': 'status-badge status-ready',
            'Validated': 'status-badge status-validated',
            'Deploying': 'status-badge status-executing',
            'Executing': 'status-badge status-executing',
            'Deployed': 'status-badge status-completed',
            'Failed': 'status-badge status-failed',
            'Cancelled': 'status-badge status-draft'
        };
        return statusMap[this.changePlan?.status] || 'status-badge';
    }

    get hasDeploymentFailed() {
        return this.changePlan?.status === 'Failed' || this.deploymentError || this.failedItems.length > 0;
    }

    get failedItems() {
        if (!this.changeItems) return [];
        return this.changeItems.filter(item => 
            item.applyStatus === 'Failed' || 
            item.validationStatus === 'Failed' ||
            (item.errorDetails && item.errorDetails.length > 0)
        );
    }

    get deploymentErrorMessage() {
        if (this.deploymentError) {
            return this.deploymentError;
        }
        
        const failed = this.failedItems;
        if (failed.length > 0) {
            const itemErrors = failed
                .filter(item => item.errorDetails)
                .map(item => `${item.fullName}: ${item.errorDetails}`)
                .slice(0, 3);
            
            if (itemErrors.length > 0) {
                const moreCount = failed.length - itemErrors.length;
                let message = itemErrors.join(' | ');
                if (moreCount > 0) {
                    message += ` (and ${moreCount} more)`;
                }
                return message;
            }
            return `${failed.length} item(s) failed. See the table below for details.`;
        }
        
        return 'Deployment failed. Please check the change items for details.';
    }

    async loadDeploymentError() {
        if (this.deploymentRunId) {
            try {
                const details = await getDeploymentRunDetails({ runId: this.deploymentRunId });
                if (details && details.errorMessage) {
                    this.deploymentError = details.errorMessage;
                    return;
                }
            } catch (e) {
                console.error('Error loading deployment details:', e);
            }
        }
        
        if (this.changePlan?.id && this.changePlan?.status === 'Failed') {
            try {
                const errors = await getDeploymentErrorsForPlan({ planId: this.changePlan.id });
                if (errors) {
                    if (errors.runError) {
                        this.deploymentError = errors.runError;
                    } else if (errors.failedItemCount > 0) {
                        const itemErrors = errors.failedItems
                            .filter(item => item.errorDetails)
                            .slice(0, 3)
                            .map(item => `${item.fullName}: ${item.errorDetails}`);
                        
                        if (itemErrors.length > 0) {
                            this.deploymentError = itemErrors.join(' | ');
                            if (errors.failedItemCount > 3) {
                                this.deploymentError += ` (and ${errors.failedItemCount - 3} more)`;
                            }
                        }
                    }
                }
            } catch (e) {
                console.error('Error loading plan errors:', e);
            }
        }
    }

    get canValidate() {
        const status = this.changePlan?.status;
        return (status === 'Draft' || status === 'Ready') && 
               this.eligibleSelectedCount > 0 && 
               !this.isValidating;
    }

    get canDeploy() {
        return this.validationComplete && 
               this.eligibleSelectedCount > 0 && 
               !this.isDeploying &&
               !this.isValidating;
    }

    get cannotValidate() {
        return !this.canValidate;
    }

    get cannotDeploy() {
        return !this.canDeploy;
    }

    get isExecuting() {
        return this.changePlan?.status === 'Executing' || this.isValidating || this.isDeploying;
    }

    get hasChangeItems() {
        return this.changeItems && this.changeItems.length > 0;
    }

    get eligibleItems() {
        return this.changeItems?.filter(item => item.eligibility === 'Eligible') || [];
    }

    get eligibleCount() {
        return this.eligibleItems.length;
    }

    get eligibleSelectedCount() {
        return this.selectedItemIds.filter(id => 
            this.eligibleItems.some(item => item.id === id)
        ).length;
    }

    get allEligibleSelected() {
        return this.eligibleItems.length > 0 && 
               this.eligibleItems.every(item => this.selectedItemIds.includes(item.id));
    }

    get someSelected() {
        return this.selectedItemIds.length > 0;
    }

    get filteredChangeItems() {
        let items = [...(this.changeItems || [])];

        if (this.eligibilityFilter === 'Failed') {
            items = items.filter(item => 
                item.applyStatus === 'Failed' || 
                item.validationStatus === 'Failed' ||
                (item.errorDetails && item.errorDetails.length > 0)
            );
        } else if (this.eligibilityFilter !== 'all') {
            items = items.filter(item => item.eligibility === this.eligibilityFilter);
        }

        items = items.map(item => {
            const isValidated = this.validationResults?.validatedIds?.includes(item.id);
            const validationError = this.validationResults?.errors?.[item.id];
            
            return {
                ...item,
                eligibilityClass: item.eligibility === 'Eligible' ? 'slds-text-color_success' : 'slds-text-color_error',
                validationStatus: this.getValidationStatus(item, isValidated, validationError),
                validationClass: this.getValidationClass(item, isValidated, validationError),
                validationIcon: this.getValidationIcon(item, isValidated, validationError),
                statusClass: this.getStatusClass(item.applyStatus),
                applyStatusClass: this.getApplyStatusClass(item.applyStatus),
                displayNotes: item.errorDetails || item.blockReason || ''
            };
        });

        if (this.sortedBy) {
            items.sort((a, b) => {
                let valueA = a[this.sortedBy] || '';
                let valueB = b[this.sortedBy] || '';

                if (typeof valueA === 'string') {
                    valueA = valueA.toLowerCase();
                    valueB = valueB.toLowerCase();
                }

                let result = 0;
                if (valueA > valueB) result = 1;
                if (valueA < valueB) result = -1;

                return this.sortedDirection === 'asc' ? result : -result;
            });
        }

        return items;
    }

    getValidationStatus(item, isValidated, validationError) {
        if (item.eligibility === 'Blocked') return 'Blocked';
        if (item.applyStatus === 'Applied') return 'Deployed';
        if (validationError) return 'Failed';
        if (isValidated) return 'Validated';
        if (!this.selectedItemIds.includes(item.id)) return 'Not Selected';
        return 'Pending';
    }

    getValidationClass(item, isValidated, validationError) {
        if (validationError) return 'slds-text-color_error';
        if (isValidated || item.applyStatus === 'Applied') return 'slds-text-color_success';
        if (item.eligibility === 'Blocked') return 'slds-text-color_error';
        return 'slds-text-color_weak';
    }

    getValidationIcon(item, isValidated, validationError) {
        if (validationError) return 'utility:error';
        if (isValidated) return 'utility:success';
        if (item.applyStatus === 'Applied') return 'utility:check';
        if (item.eligibility === 'Blocked') return 'utility:ban';
        return null;
    }

    get hasExecutionResults() {
        return this.changeItems?.some(item => 
            item.applyStatus === 'Applied' || item.applyStatus === 'Failed'
        );
    }

    get successCount() {
        return this.changeItems?.filter(item => item.applyStatus === 'Applied').length || 0;
    }

    get failedCount() {
        return this.changeItems?.filter(item => item.applyStatus === 'Failed').length || 0;
    }

    get skippedCount() {
        return this.changeItems?.filter(item => 
            item.eligibility === 'Blocked' || item.applyStatus === 'Skipped'
        ).length || 0;
    }

    get validatedCount() {
        return this.validationResults?.validatedIds?.length || 0;
    }

    get failedItemsCount() {
        return this.failedItems.length;
    }

    get hasFailedItemsCount() {
        return this.failedItemsCount > 0;
    }

    handleShowFailed() {
        this.eligibilityFilter = 'Failed';
    }

    async handleResetPlan() {
        if (!this.changePlan?.id) return;
        
        try {
            await resetPlanForRetry({ planId: this.changePlan.id });
            this.deploymentError = null;
            this._errorLoadAttempted = false;
            this.validationResults = null;
            this.validationComplete = false;
            this.eligibilityFilter = 'all';
            
            this.dispatchEvent(new CustomEvent('planreset', {
                detail: { planId: this.changePlan.id }
            }));
        } catch (error) {
            console.error('Error resetting plan:', error);
        }
    }

    get canResetPlan() {
        const status = this.changePlan?.status;
        // Allow reset from any non-Draft status, or if there's a deployment error
        return (status && status !== 'Draft') || this.deploymentError;
    }

    get validateButtonLabel() {
        if (this.isValidating) return 'Validating...';
        return `Validate Selected (${this.eligibleSelectedCount})`;
    }

    get deployButtonLabel() {
        if (this.isDeploying) return 'Deploying...';
        return `Deploy Selected (${this.validatedCount})`;
    }

    get deployButtonTitle() {
        if (!this.validationComplete) {
            return 'Run validation first before deploying';
        }
        if (this.eligibleSelectedCount === 0) {
            return 'Select components to deploy';
        }
        return 'Deploy selected components';
    }

    get selectionBadgeLabel() {
        return `${this.eligibleSelectedCount} of ${this.eligibleCount} selected`;
    }

    getStatusClass(status) {
        const classMap = {
            'Pending': 'slds-text-color_weak',
            'Applied': 'slds-text-color_success',
            'Failed': 'slds-text-color_error',
            'Skipped': 'slds-text-color_weak'
        };
        return classMap[status] || '';
    }

    getApplyStatusClass(status) {
        const classMap = {
            'Pending': 'slds-text-color_weak',
            'Applied': 'slds-text-color_success slds-text-title_bold',
            'Failed': 'slds-text-color_error slds-text-title_bold',
            'Skipped': 'slds-text-color_weak'
        };
        return classMap[status] || '';
    }

    connectedCallback() {
        this.selectAllEligible();
        if (this.changePlan?.status === 'Failed') {
            this.loadDeploymentError();
        }
    }

    renderedCallback() {
        if (this.changePlan?.status === 'Failed' && !this.deploymentError && !this._errorLoadAttempted) {
            this._errorLoadAttempted = true;
            this.loadDeploymentError();
        }
        if (this.changePlan?.status !== 'Failed') {
            this._errorLoadAttempted = false;
            this.deploymentError = null;
        }
    }

    selectAllEligible() {
        this.selectedItemIds = this.eligibleItems.map(item => item.id);
    }

    handleFilterChange(event) {
        this.eligibilityFilter = event.detail.value;
    }

    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
    }

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedItemIds = selectedRows.map(row => row.id);
        
        if (this.validationComplete) {
            this.validationComplete = false;
            this.validationResults = null;
        }
    }

    handleSelectAll() {
        this.selectAllEligible();
        this.validationComplete = false;
        this.validationResults = null;
    }

    handleSelectNone() {
        this.selectedItemIds = [];
        this.validationComplete = false;
        this.validationResults = null;
    }

    handleValidate() {
        this.isValidating = true;
        
        console.log('handleValidate starting with selectedItemIds:', this.selectedItemIds);
        
        setTimeout(() => {
            const validatedIds = this.selectedItemIds.filter(id => 
                this.eligibleItems.some(item => item.id === id)
            );
            
            console.log('Validation complete. validatedIds:', validatedIds);
            
            this.validationResults = {
                validatedIds: validatedIds,
                errors: {},
                timestamp: new Date().toISOString()
            };
            
            this.validationComplete = true;
            this.isValidating = false;
            
            this.dispatchEvent(new CustomEvent('validationcomplete', {
                detail: {
                    planId: this.changePlan.id,
                    validatedCount: validatedIds.length,
                    selectedIds: validatedIds
                }
            }));
        }, 2000);
    }

    handleDeployClick() {
        if (!this.validationComplete) {
            return;
        }
        this.showDeployConfirmation = true;
    }

    handleBackupToggle(event) {
        this.createBackupBeforeDeploy = event.target.checked;
    }

    handleCancelDeploy() {
        this.showDeployConfirmation = false;
    }

    handleConfirmDeploy() {
        this.showDeployConfirmation = false;
        this.isDeploying = true;

        const selectedIds = this.validationResults?.validatedIds || [];
        
        console.log('handleConfirmDeploy dispatching:', {
            planId: this.changePlan.id,
            selectedIds,
            selectedIdsLength: selectedIds.length,
            validationResults: this.validationResults,
            createBackup: this.createBackupBeforeDeploy
        });

        this.dispatchEvent(new CustomEvent('executeplan', {
            detail: {
                planId: this.changePlan.id,
                validateOnly: false,
                selectedIds: selectedIds,
                createBackup: this.createBackupBeforeDeploy,
                navigateToBackup: this.createBackupBeforeDeploy
            }
        }));
    }

    @api
    deploymentComplete() {
        this.isDeploying = false;
    }

    get preSelectedRows() {
        return this.selectedItemIds;
    }
}
