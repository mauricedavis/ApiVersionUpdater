import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDeploymentRunDetails from '@salesforce/apex/ApiVersionUpdaterController.getDeploymentRunDetails';
import getDeploymentErrorsForPlan from '@salesforce/apex/ApiVersionUpdaterController.getDeploymentErrorsForPlan';
import resetPlanForRetry from '@salesforce/apex/ApiVersionUpdaterController.resetPlanForRetry';
import analyzeClassForRefactor from '@salesforce/apex/ApiVersionUpdaterController.analyzeClassForRefactor';
import previewRefactor from '@salesforce/apex/ApiVersionUpdaterController.previewRefactor';
import applyRefactor from '@salesforce/apex/ApiVersionUpdaterController.applyRefactor';

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
    
    @track selectedFixOption = null;
    @track refactorPreview = null;
    @track isLoadingPreview = false;
    @track isApplyingFix = false;
    @track showRefactorModal = false;
    @track selectedComponentForFix = null;
    @track showDeployConfirmation = false;
    @track deploymentError = null;
    @track showFailedDetails = false;
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

    get detectedErrorPattern() {
        const errorText = (this.deploymentError || '') + 
            this.failedItems.map(i => i.errorDetails || '').join(' ');
        
        if (errorText.includes('uncommitted work pending') || 
            errorText.includes('commit or rollback before calling out')) {
            return 'CALLOUT_AFTER_DML';
        }
        if (errorText.includes('MIXED_DML_OPERATION')) {
            return 'MIXED_DML';
        }
        if (errorText.includes('FIELD_CUSTOM_VALIDATION_EXCEPTION')) {
            return 'VALIDATION_RULE';
        }
        if (errorText.includes('REQUIRED_FIELD_MISSING')) {
            return 'REQUIRED_FIELD';
        }
        if (errorText.includes('DUPLICATE_VALUE') || errorText.includes('DUPLICATE_USERNAME')) {
            return 'DUPLICATE';
        }
        if (errorText.includes('System.LimitException') || errorText.includes('Too many SOQL')) {
            return 'GOVERNOR_LIMIT';
        }
        return null;
    }

    get hasKnownErrorPattern() {
        return this.detectedErrorPattern !== null;
    }

    get errorPatternGuidance() {
        const patterns = {
            'CALLOUT_AFTER_DML': {
                title: 'Callout After DML Error',
                description: 'This class performs DML operations (insert/update/delete) and then makes a callout (HTTP request) in the same transaction. Salesforce requires all DML to be committed before any callouts can be made.',
                quickFix: 'Retry deployment with "No Tests" to skip test execution',
                codeFix: 'Refactor the code to separate DML from callouts.',
                canQuickFix: true,
                steps: [
                    'Open the affected Apex class (click the link below)',
                    'Find where the callout is made (look for Http.send(), HttpRequest, or external service calls)',
                    'Find any DML operations (insert, update, delete, upsert) that happen BEFORE the callout',
                    'Choose one of the fix options below to restructure the code'
                ],
                fixOptions: [
                    {
                        key: 'FUTURE_METHOD',
                        title: 'Option 1: Move callout to a @future method',
                        description: 'Best for: When the callout result is not needed immediately',
                        canAutoApply: true,
                        code: `// Before the problematic pattern:
// insert myRecord;
// HttpResponse res = http.send(req); // ERROR!

// After - move callout to async method:
insert myRecord;
MyCalloutClass.makeCalloutAsync(myRecord.Id);

// In a separate class or method:
@future(callout=true)
public static void makeCalloutAsync(Id recordId) {
    HttpRequest req = new HttpRequest();
    // ... setup request
    Http http = new Http();
    HttpResponse res = http.send(req);
}`
                    },
                    {
                        key: 'QUEUEABLE',
                        title: 'Option 2: Use Queueable for more control',
                        description: 'Best for: When you need to chain operations or handle complex logic',
                        canAutoApply: true,
                        code: `// Enqueue the callout work
insert myRecord;
System.enqueueJob(new MyCalloutQueueable(myRecord.Id));

// Queueable class:
public class MyCalloutQueueable implements Queueable, Database.AllowsCallouts {
    private Id recordId;
    
    public MyCalloutQueueable(Id recordId) {
        this.recordId = recordId;
    }
    
    public void execute(QueueableContext context) {
        HttpRequest req = new HttpRequest();
        // ... make callout here
        Http http = new Http();
        HttpResponse res = http.send(req);
    }
}`
                    },
                    {
                        key: 'REORDER',
                        title: 'Option 3: Reorder operations (callout first)',
                        description: 'Best for: When you can make the callout before any DML',
                        canAutoApply: true,
                        code: `// Move callout BEFORE any DML:
HttpRequest req = new HttpRequest();
// ... setup request
Http http = new Http();
HttpResponse res = http.send(req); // Callout first

// Now do DML after callout completes:
insert myRecord;
update anotherRecord;`
                    }
                ]
            },
            'MIXED_DML': {
                title: 'Mixed DML Operation Error',
                description: 'The code is mixing DML on setup objects (User, Profile, PermissionSet, etc.) with standard objects in the same transaction.',
                quickFix: 'Retry deployment with "No Tests" to skip test execution',
                codeFix: 'Use System.runAs() to separate setup object DML from standard object DML.',
                canQuickFix: true,
                steps: [
                    'Open the affected Apex class',
                    'Find where setup objects (User, Profile, etc.) are being inserted/updated',
                    'Find where standard objects are being modified in the same transaction',
                    'Separate them using System.runAs() or @future'
                ],
                fixOptions: [
                    {
                        title: 'Use System.runAs() in tests',
                        description: 'Separates DML contexts in test methods',
                        code: `// Insert setup object first
User testUser = new User(...);
insert testUser;

// Use System.runAs to create new DML context
System.runAs(testUser) {
    Account acc = new Account(Name = 'Test');
    insert acc;
}`
                    }
                ]
            },
            'VALIDATION_RULE': {
                title: 'Validation Rule Error',
                description: 'A validation rule is blocking the data changes. The test data may not meet the validation criteria.',
                quickFix: null,
                codeFix: 'Update the test data to satisfy the validation rule, or deactivate the rule temporarily.',
                canQuickFix: false,
                steps: [
                    'Check the error message for the validation rule name',
                    'Navigate to Setup → Object Manager → [Object] → Validation Rules',
                    'Review the rule criteria',
                    'Update your test data to satisfy the rule'
                ],
                fixOptions: []
            },
            'REQUIRED_FIELD': {
                title: 'Required Field Missing',
                description: 'A required field is not populated in the test data.',
                quickFix: null,
                codeFix: 'Update the test class to populate all required fields on the test records.',
                canQuickFix: false,
                steps: [
                    'Check the error message for the missing field name',
                    'Open the test class',
                    'Add the required field value to the test record creation'
                ],
                fixOptions: []
            },
            'DUPLICATE': {
                title: 'Duplicate Value Error',
                description: 'The test is trying to create a record with a value that already exists and must be unique.',
                quickFix: null,
                codeFix: 'Use unique values in your test data, such as adding random strings or timestamps.',
                canQuickFix: false,
                steps: [
                    'Check the error for which field has the duplicate',
                    'Update your test to use unique values'
                ],
                fixOptions: [
                    {
                        title: 'Generate unique values',
                        description: 'Use timestamp or random strings',
                        code: `String uniqueValue = 'Test_' + DateTime.now().getTime();
User u = new User(Username = uniqueValue + '@test.com', ...);`
                    }
                ]
            },
            'GOVERNOR_LIMIT': {
                title: 'Governor Limit Exceeded',
                description: 'The code exceeded a Salesforce governor limit (e.g., too many SOQL queries, DML statements, or CPU time).',
                quickFix: null,
                codeFix: 'Optimize the code to reduce SOQL queries, bulkify DML operations, or reduce processing.',
                canQuickFix: false,
                steps: [
                    'Check the specific limit mentioned in the error',
                    'Review the code for SOQL queries inside loops',
                    'Bulkify DML operations',
                    'Consider using Batch Apex for large data volumes'
                ],
                fixOptions: []
            }
        };
        return patterns[this.detectedErrorPattern] || null;
    }

    get affectedComponents() {
        return this.failedItems.map(item => ({
            id: item.id,
            name: item.fullName,
            type: item.artifactType,
            error: item.errorDetails,
            setupUrl: this.getSetupUrl(item.artifactType, item.fullName)
        }));
    }

    getSetupUrl(artifactType, fullName) {
        const baseUrl = window.location.origin;
        const encodedName = encodeURIComponent(fullName);
        
        switch (artifactType) {
            case 'ApexClass':
                return `${baseUrl}/lightning/setup/ApexClasses/home`;
            case 'ApexTrigger':
                return `${baseUrl}/lightning/setup/ApexTriggers/home`;
            case 'ApexPage':
                return `${baseUrl}/lightning/setup/ApexPages/home`;
            case 'ApexComponent':
                return `${baseUrl}/lightning/setup/ApexComponents/home`;
            default:
                return `${baseUrl}/lightning/setup/SetupOneHome/home`;
        }
    }

    handleOpenComponent(event) {
        const url = event.currentTarget.dataset.url;
        if (url) {
            window.open(url, '_blank');
        }
    }

    async handleSelectFixOption(event) {
        console.log('handleSelectFixOption called');
        const fixOption = event.currentTarget.dataset.option;
        console.log('Fix option:', fixOption);
        console.log('Failed items:', this.failedItems);
        console.log('Affected components:', this.affectedComponents);
        
        let componentName = this.affectedComponents[0]?.name;
        
        if (!componentName && this.failedItems.length > 0) {
            componentName = this.failedItems[0].fullName;
        }
        
        if (!componentName) {
            console.log('No component name found');
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'No affected component found. Please ensure there are failed items with error details.',
                variant: 'error'
            }));
            return;
        }
        
        console.log('Component name:', componentName);
        
        this.selectedFixOption = fixOption;
        this.selectedComponentForFix = componentName;
        this.isLoadingPreview = true;
        this.showRefactorModal = true;
        
        try {
            console.log('Calling previewRefactor with:', componentName, fixOption);
            const result = await previewRefactor({ 
                className: componentName, 
                fixOption: fixOption 
            });
            console.log('Preview result:', result);
            
            if (result) {
                this.refactorPreview = result;
                
                if (!result.success) {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Preview Error',
                        message: result.message || 'Preview generation failed',
                        variant: 'warning'
                    }));
                }
            } else {
                this.refactorPreview = {
                    success: false,
                    message: 'No response received from server'
                };
            }
        } catch (error) {
            console.error('Preview error:', error);
            this.refactorPreview = {
                success: false,
                message: error.body?.message || error.message || 'Failed to generate preview'
            };
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || error.message || 'Failed to generate preview',
                variant: 'error'
            }));
        } finally {
            this.isLoadingPreview = false;
        }
    }

    async handleApplyFix() {
        if (!this.selectedComponentForFix || !this.selectedFixOption) {
            return;
        }
        
        this.isApplyingFix = true;
        
        try {
            const result = await applyRefactor({ 
                className: this.selectedComponentForFix, 
                fixOption: this.selectedFixOption 
            });
            
            if (result.success) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: `Code fix applied to ${this.selectedComponentForFix}. ${result.message}`,
                    variant: 'success'
                }));
                
                this.showRefactorModal = false;
                this.refactorPreview = null;
                this.selectedFixOption = null;
                
                this.dispatchEvent(new CustomEvent('coderefactored', {
                    detail: {
                        className: this.selectedComponentForFix,
                        fixOption: this.selectedFixOption,
                        deploymentId: result.deploymentId
                    }
                }));
            } else {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: result.message,
                    variant: 'error'
                }));
            }
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || error.message || 'Failed to apply fix',
                variant: 'error'
            }));
        } finally {
            this.isApplyingFix = false;
        }
    }

    handleCloseRefactorModal() {
        this.showRefactorModal = false;
        this.refactorPreview = null;
        this.selectedFixOption = null;
        this.selectedComponentForFix = null;
    }

    get applyButtonLabel() {
        return this.isApplyingFix ? 'Applying Fix...' : 'Apply Fix to Code';
    }

    get fixOptionLabel() {
        const labels = {
            'FUTURE_METHOD': 'Option 1: @future method',
            'QUEUEABLE': 'Option 2: Queueable class',
            'REORDER': 'Option 3: Reorder operations'
        };
        return labels[this.selectedFixOption] || this.selectedFixOption;
    }

    get hasRefactorPreview() {
        return this.refactorPreview && this.refactorPreview.success === true;
    }

    get hasRefactorError() {
        return this.refactorPreview && this.refactorPreview.success === false;
    }

    handleCopyRefactoredCode() {
        if (this.refactorPreview?.refactoredCode) {
            navigator.clipboard.writeText(this.refactorPreview.refactoredCode)
                .then(() => {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Step 1 Complete!',
                        message: 'Code copied! Now click "Open Class in Setup" to paste it.',
                        variant: 'success'
                    }));
                })
                .catch(err => {
                    console.error('Copy failed:', err);
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Copy Failed',
                        message: 'Could not copy to clipboard. Please select and copy the code manually.',
                        variant: 'warning'
                    }));
                });
        }
    }

    handleOpenClassInSetup() {
        if (!this.selectedComponentForFix) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'No component selected',
                variant: 'error'
            }));
            return;
        }
        
        const baseUrl = window.location.origin;
        const classEditUrl = `${baseUrl}/lightning/setup/ApexClasses/home`;
        
        window.open(classEditUrl, '_blank');
        
        this.dispatchEvent(new ShowToastEvent({
            title: 'Setup Opened',
            message: `Find "${this.selectedComponentForFix}" in the list, click Edit, select all code (Ctrl+A), paste (Ctrl+V), and Save.`,
            variant: 'info',
            mode: 'sticky'
        }));
    }

    get showQuickFixOption() {
        return this.errorPatternGuidance?.canQuickFix === true;
    }

    handleQuickFix() {
        // Use validated items first, then selected items - NEVER fall back to all eligible
        let selectedIds = [];
        
        if (this.validationResults?.validatedIds?.length > 0) {
            selectedIds = this.validationResults.validatedIds;
        } else if (this.selectedItemIds.length > 0) {
            selectedIds = this.selectedItemIds;
        }
        
        if (selectedIds.length === 0) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'No items selected. Please select items first.',
                variant: 'error'
            }));
            return;
        }
        
        console.log('handleQuickFix - deploying items:', selectedIds.length, selectedIds);
        
        this.dispatchEvent(new CustomEvent('quickfix', {
            detail: {
                planId: this.changePlan.id,
                errorPattern: this.detectedErrorPattern,
                action: 'retry_no_tests',
                selectedItemIds: selectedIds
            }
        }));
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

    get failureTypeLabel() {
        if (this.changePlan?.status === 'Failed') {
            if (this.failedItems.some(item => item.validationStatus === 'Failed')) {
                return 'Validation Failed';
            }
            return 'Deployment Failed';
        }
        return 'Operation Failed';
    }

    get failedDetailsIcon() {
        return this.showFailedDetails ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get failedItemsWithErrors() {
        return this.failedItems.map(item => ({
            ...item,
            errorDetails: item.errorDetails || item.notes || 'Unknown error - check component in Setup'
        }));
    }

    handleToggleFailedDetails() {
        this.showFailedDetails = !this.showFailedDetails;
    }

    handleRetryValidation() {
        this.deploymentError = null;
        this.showFailedDetails = false;
        this.validationComplete = false;
        this.validationResults = null;
        
        this.dispatchEvent(new CustomEvent('retryvalidation', {
            detail: { planId: this.changePlan.id }
        }));
        
        this.handleValidate();
    }

    handleExcludeFailed() {
        const failedIds = new Set(this.failedItems.map(item => item.id));
        this.selectedItemIds = this.selectedItemIds.filter(id => !failedIds.has(id));
        
        this.deploymentError = null;
        this.showFailedDetails = false;
        
        this.dispatchEvent(new ShowToastEvent({
            title: 'Items Excluded',
            message: `${failedIds.size} failed item(s) have been deselected. You can now retry validation.`,
            variant: 'info'
        }));
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

    handleTestLevelChange(event) {
        this.selectedTestLevel = event.detail.value;
    }

    get showTestLevelWarning() {
        return this.selectedTestLevel === 'NoTestRun';
    }

    get testLevelWarningMessage() {
        if (this.selectedTestLevel === 'NoTestRun') {
            return 'Deploying without tests skips validation. Ensure your components are tested separately.';
        }
        return '';
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
            createBackup: this.createBackupBeforeDeploy,
            testLevel: this.selectedTestLevel
        });

        this.dispatchEvent(new CustomEvent('executeplan', {
            detail: {
                planId: this.changePlan.id,
                validateOnly: false,
                selectedIds: selectedIds,
                createBackup: this.createBackupBeforeDeploy,
                navigateToBackup: this.createBackupBeforeDeploy,
                testLevel: this.selectedTestLevel
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
