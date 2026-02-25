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
    @api hasBackup = false;
    @api currentStep = 0;

    get targetVersion() {
        return this.targetApiVersion || '56.0';
    }

    get hasScan() {
        return this.session?.currentScanId || this.scanName;
    }

    get hasPlan() {
        return this.session?.currentChangePlanId || this.planName;
    }

    get hasDeployment() {
        return this.session?.currentDeploymentRunId || this.deploymentStatus;
    }

    get hasFindings() {
        return this.findingsCount > 0 || this.componentsNeedingUpgrade > 0;
    }

    get displayScanName() {
        return this.scanName || this.session?.currentScanName || '';
    }

    get displayScanStatus() {
        return this.scanStatus || this.session?.currentScanStatus || '-';
    }

    get displayPlanName() {
        return this.planName || this.session?.currentChangePlanName || '';
    }

    get displayPlanStatus() {
        return this.planStatus || this.session?.currentChangePlanStatus || '-';
    }

    get displayPlanItemCount() {
        return this.planItemCount || this.session?.currentChangePlanItemCount || 0;
    }

    get displayDeploymentStatus() {
        return this.deploymentStatus || this.session?.currentDeploymentRunStatus || '-';
    }

    get isScanRunning() {
        const status = this.displayScanStatus;
        return status === 'Running' || status === 'Queued';
    }

    get isScanComplete() {
        const status = this.displayScanStatus;
        return status === 'Completed' || status === 'Failed';
    }

    get isDeploymentRunning() {
        const status = this.displayDeploymentStatus;
        return status === 'Running' || status === 'Queued' || status === 'Processing';
    }

    get isDeploymentComplete() {
        const status = this.displayDeploymentStatus;
        return status === 'Completed' || status === 'Succeeded';
    }

    get deploymentProgress() {
        const status = this.displayDeploymentStatus;
        if (status === 'Queued') return 25;
        if (status === 'Running' || status === 'Processing') return 60;
        if (status === 'Completed' || status === 'Succeeded') return 100;
        return 0;
    }

    get isPlanReady() {
        const status = this.displayPlanStatus;
        return status === 'Draft' || status === 'Ready' || status === 'Validated';
    }

    get showStartScanButton() {
        return !this.hasScan && !this.isScanRunning;
    }

    get showCreatePlanButton() {
        return this.hasFindings && !this.hasPlan && this.isScanComplete;
    }
    
    get showReviewButtons() {
        return this.isScanComplete && this.hasFindings;
    }

    get showDeployButton() {
        return this.hasPlan && this.isPlanReady && !this.hasDeployment;
    }

    get showRestoreButton() {
        return this.hasDeployment && this.hasBackup;
    }

    get scanCardClass() {
        let classes = 'status-card';
        if (this.currentStep === 1) classes += ' card-active';
        if (this.isScanComplete) classes += ' card-complete';
        if (this.isScanRunning) classes += ' card-in-progress';
        return classes;
    }

    get findingsCardClass() {
        let classes = 'status-card';
        if (this.currentStep === 2) classes += ' card-active';
        if (this.hasFindings && this.isScanComplete) classes += ' card-complete';
        return classes;
    }

    get planCardClass() {
        let classes = 'status-card';
        if (this.currentStep === 3) classes += ' card-active';
        if (this.hasPlan) classes += ' card-complete';
        return classes;
    }

    get deploymentCardClass() {
        let classes = 'status-card';
        if (this.currentStep === 4) classes += ' card-active';
        if (this.hasDeployment) {
            const status = this.displayDeploymentStatus;
            if (status === 'Completed' || status === 'Succeeded') {
                classes += ' card-complete';
            } else if (status === 'Failed') {
                classes += ' card-error';
            } else {
                classes += ' card-in-progress';
            }
        }
        return classes;
    }

    get isScanSelected() {
        return this.currentStep === 1;
    }

    get isReviewSelected() {
        return this.currentStep === 2;
    }

    get isPlanSelected() {
        return this.currentStep === 3;
    }

    get isDeploySelected() {
        return this.currentStep === 4;
    }

    get isScanStepComplete() {
        return this.isScanComplete;
    }

    get isReviewStepComplete() {
        return this.hasPlan;
    }

    get isPlanStepComplete() {
        return this.hasDeployment;
    }

    get isDeployStepComplete() {
        const status = this.displayDeploymentStatus;
        return status === 'Completed' || status === 'Succeeded';
    }

    get scanStepBadgeClass() {
        if (this.currentStep === 1) return 'step-badge step-badge-active';
        return 'step-badge';
    }

    get findingsStepBadgeClass() {
        if (this.currentStep === 2) return 'step-badge step-badge-active';
        return 'step-badge';
    }

    get planStepBadgeClass() {
        if (this.currentStep === 3) return 'step-badge step-badge-active';
        return 'step-badge';
    }

    get deployStepBadgeClass() {
        if (this.currentStep === 4) return 'step-badge step-badge-active';
        return 'step-badge';
    }

    get connector1Class() {
        if (this.currentStep >= 2 || this.isScanComplete) return 'connector connector-complete';
        if (this.currentStep === 1 && this.isScanRunning) return 'connector connector-active';
        return 'connector';
    }

    get connector2Class() {
        if (this.currentStep >= 3) return 'connector connector-complete';
        if (this.currentStep === 2) return 'connector connector-active';
        return 'connector';
    }

    get connector3Class() {
        if (this.currentStep >= 4) return 'connector connector-complete';
        if (this.currentStep === 3) return 'connector connector-active';
        return 'connector';
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

    get showClearButton() {
        return this.hasScan || this.hasPlan || this.hasDeployment;
    }

    handleClearSession() {
        this.dispatchEvent(new CustomEvent('clearsession'));
    }

    handleStartScan(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('startscan'));
    }

    handleCancelScan(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('cancelscan'));
    }

    handleScanClick() {
        if (this.hasScan) {
            this.dispatchEvent(new CustomEvent('viewscan', {
                detail: { scanId: this.session?.currentScanId }
            }));
        }
    }

    handleFindingsClick() {
        if (this.hasFindings) {
            this.dispatchEvent(new CustomEvent('viewfindings', {
                detail: { scanId: this.session?.currentScanId }
            }));
        }
    }

    handleCreatePlan(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('createplan', {
            detail: { scanId: this.session?.currentScanId }
        }));
    }

    handlePlanClick() {
        if (this.hasPlan) {
            this.dispatchEvent(new CustomEvent('viewplan', {
                detail: { planId: this.session?.currentChangePlanId }
            }));
        }
    }

    handleDeployClick(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('deploynow', {
            detail: { planId: this.session?.currentChangePlanId }
        }));
    }

    handleDeploymentClick() {
        if (this.hasDeployment) {
            this.dispatchEvent(new CustomEvent('viewdeployment', {
                detail: { deploymentRunId: this.session?.currentDeploymentRunId }
            }));
        }
    }

    handleRestoreClick(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('restore', {
            detail: { deploymentRunId: this.session?.currentDeploymentRunId }
        }));
    }
}
