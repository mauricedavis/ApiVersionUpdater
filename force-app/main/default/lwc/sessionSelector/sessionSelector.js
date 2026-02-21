import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import getScanHistory from '@salesforce/apex/SessionService.getScanHistory';
import getPlanHistory from '@salesforce/apex/SessionService.getPlanHistory';

export default class SessionSelector extends LightningElement {
    @api mode = 'scan';
    @api currentScanId;
    @api currentPlanId;

    @track isOpen = false;
    @track searchTerm = '';

    wiredScansResult;
    wiredPlansResult;
    scans = [];
    plans = [];

    @wire(getScanHistory)
    wiredScans(result) {
        this.wiredScansResult = result;
        if (result.data) {
            this.scans = result.data;
        } else if (result.error) {
            console.error('Error loading scans:', result.error);
        }
    }

    @wire(getPlanHistory)
    wiredPlans(result) {
        this.wiredPlansResult = result;
        if (result.data) {
            this.plans = result.data;
        } else if (result.error) {
            console.error('Error loading plans:', result.error);
        }
    }

    get isScanMode() {
        return this.mode === 'scan';
    }

    get isPlanMode() {
        return this.mode === 'plan';
    }

    get dropdownIcon() {
        return this.isOpen ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get selectorLabel() {
        return this.isScanMode ? 'Select Scan' : 'Select Plan';
    }

    get currentLabel() {
        if (this.isScanMode) {
            const scan = this.scans.find(s => s.id === this.currentScanId);
            return scan ? scan.displayName : 'Select a scan...';
        } else {
            const plan = this.plans.find(p => p.id === this.currentPlanId);
            return plan ? plan.displayName : 'Select a plan...';
        }
    }

    get items() {
        const itemList = this.isScanMode ? this.scans : this.plans;
        
        if (!this.searchTerm) {
            return itemList.map(item => {
                const isSelected = this.isScanMode 
                    ? item.id === this.currentScanId 
                    : item.id === this.currentPlanId;
                return {
                    ...item,
                    isSelected,
                    itemClass: isSelected ? 'item item-selected' : 'item',
                    statusClass: this.getStatusClass(item.status)
                };
            });
        }

        const search = this.searchTerm.toLowerCase();
        return itemList
            .filter(item => 
                item.displayName?.toLowerCase().includes(search) ||
                item.name?.toLowerCase().includes(search)
            )
            .map(item => {
                const isSelected = this.isScanMode 
                    ? item.id === this.currentScanId 
                    : item.id === this.currentPlanId;
                return {
                    ...item,
                    isSelected,
                    itemClass: isSelected ? 'item item-selected' : 'item',
                    statusClass: this.getStatusClass(item.status)
                };
            });
    }

    get hasItems() {
        return this.items.length > 0;
    }

    get noItemsMessage() {
        if (this.searchTerm) {
            return `No ${this.isScanMode ? 'scans' : 'plans'} matching "${this.searchTerm}"`;
        }
        return `No ${this.isScanMode ? 'scans' : 'plans'} found. Start a new scan to get started.`;
    }

    getStatusClass(status) {
        const statusMap = {
            'Completed': 'status-badge status-success',
            'Succeeded': 'status-badge status-success',
            'Deployed': 'status-badge status-success',
            'Running': 'status-badge status-pending',
            'Queued': 'status-badge status-pending',
            'Executing': 'status-badge status-pending',
            'Draft': 'status-badge status-info',
            'Ready': 'status-badge status-info',
            'Validated': 'status-badge status-info',
            'Failed': 'status-badge status-error'
        };
        return statusMap[status] || 'status-badge status-neutral';
    }

    toggleDropdown() {
        this.isOpen = !this.isOpen;
        if (this.isOpen) {
            this.refreshData();
        }
    }

    closeDropdown() {
        this.isOpen = false;
        this.searchTerm = '';
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    handleItemSelect(event) {
        const itemId = event.currentTarget.dataset.id;
        
        this.dispatchEvent(new CustomEvent('select', {
            detail: {
                id: itemId,
                type: this.mode
            }
        }));

        this.closeDropdown();
    }

    handleNewScan() {
        this.dispatchEvent(new CustomEvent('newscan'));
        this.closeDropdown();
    }

    async refreshData() {
        await Promise.all([
            refreshApex(this.wiredScansResult),
            refreshApex(this.wiredPlansResult)
        ]);
    }

    handleClickOutside(event) {
        if (this.isOpen && !this.template.querySelector('.selector-container').contains(event.target)) {
            this.closeDropdown();
        }
    }

    connectedCallback() {
        document.addEventListener('click', this.handleClickOutside.bind(this));
    }

    disconnectedCallback() {
        document.removeEventListener('click', this.handleClickOutside.bind(this));
    }
}
