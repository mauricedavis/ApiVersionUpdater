import { LightningElement, api, track } from 'lwc';

export default class InventoryPanel extends LightningElement {
    @api inventoryCounts = {};
    @api versionDistribution = {};
    @api targetVersion = '65.0';
    @api scopePolicy = 'CustomOnly';
    @api complianceMetrics = null;

    @track selectedDistributionType = 'ApexClass';

    typeOptions = [
        { label: 'Apex Classes', value: 'ApexClass' },
        { label: 'Apex Triggers', value: 'ApexTrigger' },
        { label: 'Visualforce Pages', value: 'ApexPage' },
        { label: 'Visualforce Components', value: 'ApexComponent' }
    ];

    get hasComplianceData() {
        console.log('inventoryPanel - complianceMetrics:', this.complianceMetrics);
        console.log('inventoryPanel - versionDistribution:', this.versionDistribution);
        console.log('inventoryPanel - targetVersion:', this.targetVersion);
        return this.complianceMetrics && this.complianceMetrics.totalComponents > 0;
    }

    get compliancePercentage() {
        if (!this.complianceMetrics) return 0;
        return Math.round(this.complianceMetrics.compliancePercentage);
    }

    get complianceRingStyle() {
        const percentage = this.compliancePercentage;
        const degrees = (percentage / 100) * 360;
        const color = this.getComplianceColor(percentage);
        
        if (percentage <= 50) {
            return `background: conic-gradient(${color} ${degrees}deg, #e0e5ee ${degrees}deg);`;
        } else {
            return `background: conic-gradient(${color} ${degrees}deg, #e0e5ee ${degrees}deg);`;
        }
    }

    get complianceTextColor() {
        const percentage = this.compliancePercentage;
        if (percentage >= 80) return 'compliance-text-success';
        if (percentage >= 50) return 'compliance-text-warning';
        return 'compliance-text-error';
    }

    getComplianceColor(percentage) {
        if (percentage >= 80) return '#2e844a';
        if (percentage >= 50) return '#ff9a3c';
        return '#c23934';
    }

    get complianceStatusLabel() {
        const percentage = this.compliancePercentage;
        if (percentage >= 90) return 'Excellent';
        if (percentage >= 80) return 'Good';
        if (percentage >= 60) return 'Fair';
        if (percentage >= 40) return 'Needs Work';
        return 'Critical';
    }

    get complianceStatusClass() {
        const percentage = this.compliancePercentage;
        if (percentage >= 80) return 'slds-badge slds-badge_success';
        if (percentage >= 50) return 'slds-badge slds-badge_warning';
        return 'slds-badge slds-badge_error';
    }

    get typeComplianceCards() {
        if (!this.complianceMetrics || !this.complianceMetrics.byType) return [];
        
        const typeLabels = {
            'ApexClass': 'Apex Classes',
            'ApexTrigger': 'Apex Triggers',
            'ApexPage': 'VF Pages',
            'ApexComponent': 'VF Components'
        };

        const typeIcons = {
            'ApexClass': 'utility:apex',
            'ApexTrigger': 'utility:flow',
            'ApexPage': 'utility:page',
            'ApexComponent': 'utility:component_customization'
        };

        return Object.entries(this.complianceMetrics.byType).map(([type, data]) => {
            const pct = Math.round(data.compliancePercentage);
            return {
                type,
                label: typeLabels[type] || type,
                icon: typeIcons[type] || 'utility:apex',
                total: data.total,
                compliant: data.compliant,
                nonCompliant: data.nonCompliant,
                percentage: pct,
                progressStyle: `width: ${pct}%;`,
                progressClass: pct >= 80 ? 'progress-success' : (pct >= 50 ? 'progress-warning' : 'progress-error'),
                statusIcon: pct >= 80 ? 'utility:success' : (pct >= 50 ? 'utility:warning' : 'utility:error'),
                statusVariant: pct >= 80 ? 'success' : (pct >= 50 ? 'warning' : 'error')
            };
        });
    }

    get totalComponents() {
        if (this.complianceMetrics) {
            return this.complianceMetrics.totalComponents;
        }
        return Object.values(this.inventoryCounts).reduce((sum, count) => sum + (count || 0), 0);
    }

    get compliantCount() {
        return this.complianceMetrics ? this.complianceMetrics.compliantComponents : 0;
    }

    get nonCompliantCount() {
        return this.complianceMetrics ? this.complianceMetrics.nonCompliantComponents : 0;
    }

    get oldestVersion() {
        return this.complianceMetrics ? this.complianceMetrics.oldestVersion : '-';
    }

    get newestVersion() {
        return this.complianceMetrics ? this.complianceMetrics.newestVersion : '-';
    }

    get versionsToUpgrade() {
        return this.complianceMetrics ? this.complianceMetrics.versionsToUpgrade : 0;
    }

    get hasDistributionData() {
        return this.versionDistribution && Object.keys(this.versionDistribution).length > 0;
    }

    get distributionBars() {
        if (!this.versionDistribution) return [];

        const entries = Object.entries(this.versionDistribution);
        const maxCount = Math.max(...entries.map(([, count]) => count), 1);
        const targetNum = parseFloat(this.targetVersion);

        return entries
            .sort(([a], [b]) => parseFloat(b) - parseFloat(a))
            .slice(0, 12)
            .map(([version, count]) => {
                const percentage = Math.round((count / maxCount) * 100);
                const versionNum = parseFloat(version);
                const isCompliant = versionNum >= targetNum;

                return {
                    version,
                    count,
                    percentage,
                    isCompliant,
                    barClass: isCompliant ? 'bar-compliant' : 'bar-non-compliant',
                    barStyle: `width: ${percentage}%;`,
                    versionClass: isCompliant ? 'version-compliant' : 'version-non-compliant'
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
