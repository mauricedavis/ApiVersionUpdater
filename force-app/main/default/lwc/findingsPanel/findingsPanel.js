import { LightningElement, api, track } from 'lwc';

export default class FindingsPanel extends LightningElement {
    @api scanId;
    @api findings = [];
    @api findingsSummary = {};

    @track severityFilter = 'all';
    @track categoryFilter = 'all';
    @track searchText = '';

    severityOptions = [
        { label: 'All Severities', value: 'all' },
        { label: 'Critical', value: 'Critical' },
        { label: 'Warning', value: 'Warning' },
        { label: 'Info', value: 'Info' }
    ];

    categoryOptions = [
        { label: 'All Categories', value: 'all' },
        { label: 'Breaking Change', value: 'BreakingChange' },
        { label: 'Deprecation', value: 'Deprecation' },
        { label: 'Version Risk', value: 'VersionRisk' },
        { label: 'Drift', value: 'Drift' },
        { label: 'Code Quality', value: 'CodeQuality' }
    ];

    get totalFindings() {
        return this.findings?.length || 0;
    }

    get criticalCount() {
        return this.findingsSummary?.Critical || 0;
    }

    get warningCount() {
        return this.findingsSummary?.Warning || 0;
    }

    get infoCount() {
        return this.findingsSummary?.Info || 0;
    }

    get hasFindings() {
        return this.findings && this.findings.length > 0;
    }

    get hasBlockingFindings() {
        return this.findings?.some(f => f.isBlocking) || false;
    }

    get filteredFindings() {
        let filtered = [...(this.findings || [])];

        if (this.severityFilter !== 'all') {
            filtered = filtered.filter(f => f.severity === this.severityFilter);
        }

        if (this.categoryFilter !== 'all') {
            filtered = filtered.filter(f => f.category === this.categoryFilter);
        }

        if (this.searchText) {
            const search = this.searchText.toLowerCase();
            filtered = filtered.filter(f => 
                f.artifactName?.toLowerCase().includes(search) ||
                f.summary?.toLowerCase().includes(search) ||
                f.ruleId?.toLowerCase().includes(search)
            );
        }

        return filtered.map(f => ({
            ...f,
            severityClass: this.getSeverityClass(f.severity),
            severityIcon: this.getSeverityIcon(f.severity)
        }));
    }

    getSeverityClass(severity) {
        const classMap = {
            'Critical': 'severity-critical',
            'Warning': 'severity-warning',
            'Info': 'severity-info'
        };
        return classMap[severity] || '';
    }

    getSeverityIcon(severity) {
        const iconMap = {
            'Critical': 'utility:error',
            'Warning': 'utility:warning',
            'Info': 'utility:info'
        };
        return iconMap[severity] || 'utility:info';
    }

    handleFilterChange(event) {
        const field = event.target.name;
        this[field] = event.target.value;
    }

    handleSearchChange(event) {
        this.searchText = event.target.value;
    }

    handleCreatePlan() {
        this.dispatchEvent(new CustomEvent('createplan', {
            detail: {
                scanId: this.scanId
            }
        }));
    }
}
