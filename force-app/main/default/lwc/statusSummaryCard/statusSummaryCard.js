import { LightningElement, api } from 'lwc';

export default class StatusSummaryCard extends LightningElement {
    @api session;
    @api scanName;
    @api scanStatus;
    @api scanStartedAt;
    @api findingsCount = 0;
    @api alertsCount = 0;
    @api componentsNeedingUpgrade = 0;
    @api planName;
    @api planStatus;
    @api planItemCount = 0;
    @api deploymentStatus;
    @api targetApiVersion;

    get hasScan() {
        return this.session?.currentScanId || this.scanName;
    }

    get hasPlan() {
        return this.session?.currentChangePlanId || this.planName;
    }

    get hasDeployment() {
        return this.session?.currentDeploymentRunId || this.deploymentStatus;
    }

    get displayScanName() {
        return this.session?.currentScanName || this.scanName || 'No scan selected';
    }

    get displayScanStatus() {
        return this.session?.currentScanStatus || this.scanStatus || '-';
    }

    get displayPlanName() {
        return this.session?.currentChangePlanName || this.planName || 'No plan created';
    }

    get displayPlanStatus() {
        return this.session?.currentChangePlanStatus || this.planStatus || '-';
    }

    get displayPlanItemCount() {
        return this.session?.currentChangePlanItemCount || this.planItemCount || 0;
    }

    get sourceScanName() {
        return this.session?.currentChangePlanSourceScanName || null;
    }

    get displayDeploymentStatus() {
        return this.session?.currentDeploymentRunStatus || this.deploymentStatus || '-';
    }

    get scanStatusClass() {
        const status = this.displayScanStatus;
        if (status === 'Completed') return 'status-badge status-success';
        if (status === 'Running' || status === 'Queued') return 'status-badge status-pending';
        if (status === 'Failed') return 'status-badge status-error';
        return 'status-badge status-neutral';
    }

    get planStatusClass() {
        const status = this.displayPlanStatus;
        if (status === 'Completed' || status === 'Deployed') return 'status-badge status-success';
        if (status === 'Executing' || status === 'Deploying') return 'status-badge status-pending';
        if (status === 'Draft' || status === 'Ready' || status === 'Validated') return 'status-badge status-info';
        if (status === 'Failed') return 'status-badge status-error';
        return 'status-badge status-neutral';
    }

    get deploymentStatusClass() {
        const status = this.displayDeploymentStatus;
        if (status === 'Completed' || status === 'Succeeded') return 'status-badge status-success';
        if (status === 'Running' || status === 'Queued') return 'status-badge status-pending';
        if (status === 'Failed') return 'status-badge status-error';
        return 'status-badge status-neutral';
    }

    get formattedScanDate() {
        const date = this.session?.currentScanStartedAt || this.scanStartedAt;
        if (!date) return '-';
        return new Date(date).toLocaleString();
    }

    get showClearButton() {
        return this.hasScan || this.hasPlan || this.hasDeployment;
    }

    handleClearSession() {
        this.dispatchEvent(new CustomEvent('clearsession'));
    }

    handleScanClick() {
        if (this.hasScan) {
            this.dispatchEvent(new CustomEvent('viewscan', {
                detail: { scanId: this.session?.currentScanId }
            }));
        }
    }

    handlePlanClick() {
        if (this.hasPlan) {
            this.dispatchEvent(new CustomEvent('viewplan', {
                detail: { planId: this.session?.currentChangePlanId }
            }));
        }
    }

    handleDeploymentClick() {
        if (this.hasDeployment) {
            this.dispatchEvent(new CustomEvent('viewdeployment', {
                detail: { deploymentRunId: this.session?.currentDeploymentRunId }
            }));
        }
    }

    get hasDeploymentStats() {
        return this.session?.currentDeploymentTotalProcessed > 0;
    }

    get deploymentSuccessCount() {
        return this.session?.currentDeploymentSuccessCount || 0;
    }

    get deploymentFailCount() {
        return this.session?.currentDeploymentFailCount || 0;
    }

    get hasDeploymentFailures() {
        return this.deploymentFailCount > 0;
    }
}
