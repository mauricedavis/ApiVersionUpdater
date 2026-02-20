import { LightningElement, api, track } from 'lwc';

export default class InventoryPanel extends LightningElement {
    @api inventoryCounts = {};
    @api versionDistribution = {};
    @api targetVersion = '65.0';

    @track selectedDistributionType = 'ApexClass';

    typeOptions = [
        { label: 'Apex Classes', value: 'ApexClass' },
        { label: 'Apex Triggers', value: 'ApexTrigger' },
        { label: 'Visualforce Pages', value: 'ApexPage' },
        { label: 'Visualforce Components', value: 'ApexComponent' }
    ];

    get countCards() {
        return [
            {
                type: 'ApexClass',
                label: 'Apex Classes',
                count: this.inventoryCounts.ApexClass || 0,
                icon: 'utility:apex'
            },
            {
                type: 'ApexTrigger',
                label: 'Apex Triggers',
                count: this.inventoryCounts.ApexTrigger || 0,
                icon: 'utility:flow'
            },
            {
                type: 'ApexPage',
                label: 'VF Pages',
                count: this.inventoryCounts.ApexPage || 0,
                icon: 'utility:page'
            },
            {
                type: 'ApexComponent',
                label: 'VF Components',
                count: this.inventoryCounts.ApexComponent || 0,
                icon: 'utility:component_customization'
            }
        ];
    }

    get totalComponents() {
        return Object.values(this.inventoryCounts).reduce((sum, count) => sum + (count || 0), 0);
    }

    get hasDistributionData() {
        return this.versionDistribution && Object.keys(this.versionDistribution).length > 0;
    }

    get distributionBars() {
        if (!this.versionDistribution) return [];

        const entries = Object.entries(this.versionDistribution);
        const maxCount = Math.max(...entries.map(([, count]) => count), 1);

        return entries
            .sort(([a], [b]) => parseFloat(b) - parseFloat(a))
            .slice(0, 10)
            .map(([version, count]) => {
                const percentage = Math.round((count / maxCount) * 100);
                const targetNum = parseFloat(this.targetVersion);
                const versionNum = parseFloat(version);
                const isBelow = versionNum < targetNum;

                return {
                    version,
                    count,
                    percentage,
                    barStyle: `width: ${percentage}%; background-color: ${isBelow ? '#c23934' : '#2e844a'};`
                };
            });
    }

    get belowTargetCount() {
        if (!this.versionDistribution) return 0;

        const targetNum = parseFloat(this.targetVersion);
        return Object.entries(this.versionDistribution)
            .filter(([version]) => parseFloat(version) < targetNum)
            .reduce((sum, [, count]) => sum + count, 0);
    }

    handleTypeChange(event) {
        this.selectedDistributionType = event.detail.value;
        this.dispatchEvent(new CustomEvent('typechange', {
            detail: { type: this.selectedDistributionType }
        }));
    }

    handleStartScan() {
        this.dispatchEvent(new CustomEvent('startscan'));
    }

    handleRefresh() {
        this.dispatchEvent(new CustomEvent('refresh'));
    }
}
