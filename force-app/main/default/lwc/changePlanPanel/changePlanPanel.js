import { LightningElement, api, track } from 'lwc';

export default class ChangePlanPanel extends LightningElement {
    @api changePlan = {};
    @api changeItems = [];

    @track eligibilityFilter = 'all';
    @track sortedBy = 'unitNumber';
    @track sortedDirection = 'asc';

    eligibilityOptions = [
        { label: 'All Items', value: 'all' },
        { label: 'Eligible Only', value: 'Eligible' },
        { label: 'Blocked Only', value: 'Blocked' }
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
            label: 'Status', 
            fieldName: 'applyStatus', 
            type: 'text',
            sortable: true,
            initialWidth: 100,
            cellAttributes: { class: { fieldName: 'statusClass' } }
        },
        { 
            label: 'Notes', 
            fieldName: 'blockReason', 
            type: 'text',
            wrapText: true
        }
    ];

    get planStatusClass() {
        const statusMap = {
            'Draft': 'status-badge status-draft',
            'Ready': 'status-badge status-ready',
            'Executing': 'status-badge status-executing',
            'Completed': 'status-badge status-completed',
            'PartiallyCompleted': 'status-badge status-partial',
            'Failed': 'status-badge status-failed'
        };
        return statusMap[this.changePlan?.status] || 'status-badge';
    }

    get canExecute() {
        const status = this.changePlan?.status;
        return status === 'Draft' || status === 'Ready';
    }

    get isExecuting() {
        return this.changePlan?.status === 'Executing';
    }

    get hasChangeItems() {
        return this.changeItems && this.changeItems.length > 0;
    }

    get filteredChangeItems() {
        let items = [...(this.changeItems || [])];

        if (this.eligibilityFilter !== 'all') {
            items = items.filter(item => item.eligibility === this.eligibilityFilter);
        }

        items = items.map(item => ({
            ...item,
            eligibilityClass: item.eligibility === 'Eligible' ? 'slds-text-color_success' : 'slds-text-color_error',
            statusClass: this.getStatusClass(item.applyStatus)
        }));

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

    getStatusClass(status) {
        const classMap = {
            'Pending': 'slds-text-color_weak',
            'Applied': 'slds-text-color_success',
            'Failed': 'slds-text-color_error',
            'Skipped': 'slds-text-color_weak'
        };
        return classMap[status] || '';
    }

    handleFilterChange(event) {
        this.eligibilityFilter = event.detail.value;
    }

    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
    }

    handleValidate() {
        this.dispatchEvent(new CustomEvent('executeplan', {
            detail: {
                planId: this.changePlan.id,
                validateOnly: true
            }
        }));
    }

    handleDeploy() {
        this.dispatchEvent(new CustomEvent('executeplan', {
            detail: {
                planId: this.changePlan.id,
                validateOnly: false
            }
        }));
    }
}
