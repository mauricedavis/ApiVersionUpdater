import { LightningElement, api } from 'lwc';

const WORKFLOW_STEPS = [
    { id: 1, label: 'Scan', description: 'Run compliance scan', icon: 'utility:search' },
    { id: 2, label: 'Review', description: 'Review findings', icon: 'utility:preview' },
    { id: 3, label: 'Plan', description: 'Create change plan', icon: 'utility:edit' },
    { id: 4, label: 'Deploy', description: 'Deploy changes', icon: 'utility:upload' },
    { id: 5, label: 'Backup', description: 'Backup & restore', icon: 'utility:backup' }
];

export default class ProgressStepper extends LightningElement {
    @api currentStep = 0;
    @api completedSteps = [];

    get steps() {
        return WORKFLOW_STEPS.map(step => {
            const isCompleted = this.completedSteps.includes(step.id) || step.id < this.currentStep;
            const isCurrent = step.id === this.currentStep;
            const isDisabled = step.id > this.currentStep && !isCompleted;

            return {
                ...step,
                isCompleted,
                isCurrent,
                isDisabled,
                stepClass: this.getStepClass(isCompleted, isCurrent, isDisabled),
                iconClass: this.getIconClass(isCompleted, isCurrent),
                connectorClass: this.getConnectorClass(step.id, isCompleted)
            };
        });
    }

    getStepClass(isCompleted, isCurrent, isDisabled) {
        let classes = 'step';
        if (isCompleted) classes += ' step-completed';
        if (isCurrent) classes += ' step-current';
        if (isDisabled) classes += ' step-disabled';
        return classes;
    }

    getIconClass(isCompleted, isCurrent) {
        if (isCompleted) return 'step-icon step-icon-completed';
        if (isCurrent) return 'step-icon step-icon-current';
        return 'step-icon step-icon-pending';
    }

    getConnectorClass(stepId, isCompleted) {
        if (stepId === WORKFLOW_STEPS.length) return 'connector connector-hidden';
        if (isCompleted || stepId < this.currentStep) return 'connector connector-completed';
        return 'connector connector-pending';
    }

    handleStepClick(event) {
        const stepId = parseInt(event.currentTarget.dataset.stepId, 10);
        const step = WORKFLOW_STEPS.find(s => s.id === stepId);
        
        if (step && (this.completedSteps.includes(stepId) || stepId <= this.currentStep)) {
            this.dispatchEvent(new CustomEvent('stepclick', {
                detail: { stepId, stepLabel: step.label }
            }));
        }
    }

    get progressPercentage() {
        if (this.currentStep === 0) return 0;
        return Math.round(((this.currentStep - 1) / (WORKFLOW_STEPS.length - 1)) * 100);
    }

    get progressLabel() {
        const current = WORKFLOW_STEPS.find(s => s.id === this.currentStep);
        return current ? `Step ${this.currentStep} of ${WORKFLOW_STEPS.length}: ${current.label}` : 'Not Started';
    }
}
