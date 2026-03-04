import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import checkSetupStatus from '@salesforce/apex/ToolingApiService.checkSetupStatus';

export default class SetupWizard extends LightningElement {
    @track isLoading = true;
    @track setupStatus = null;
    @track currentStep = 1;
    @track error = null;

    connectedCallback() {
        this.checkStatus();
    }

    async checkStatus() {
        this.isLoading = true;
        this.error = null;
        
        try {
            this.setupStatus = await checkSetupStatus();
            
            if (this.setupStatus.isConfigured) {
                this.currentStep = 4;
            } else if (this.setupStatus.hasNamedCredential && !this.setupStatus.hasUserAuthenticated) {
                this.currentStep = 3;
            } else if (this.setupStatus.hasExternalCredential) {
                this.currentStep = 2;
            } else {
                this.currentStep = 1;
            }
        } catch (err) {
            console.error('Setup status check failed:', err);
            this.error = err.body?.message || err.message || 'Failed to check setup status';
        } finally {
            this.isLoading = false;
        }
    }

    handleRefresh() {
        this.checkStatus();
    }

    handleSkipSetup() {
        this.dispatchEvent(new CustomEvent('setupskipped'));
    }

    handleSetupComplete() {
        this.dispatchEvent(new CustomEvent('setupcomplete'));
    }

    get isFullyConfigured() {
        return this.setupStatus?.isConfigured === true;
    }

    get showStep1() {
        return this.currentStep === 1;
    }

    get showStep2() {
        return this.currentStep === 2;
    }

    get showStep3() {
        return this.currentStep === 3;
    }

    get showStep4() {
        return this.currentStep === 4;
    }

    get step1Status() {
        return this.setupStatus?.hasExternalCredential ? 'completed' : (this.currentStep === 1 ? 'active' : 'pending');
    }

    get step2Status() {
        return this.setupStatus?.hasNamedCredential ? 'completed' : (this.currentStep === 2 ? 'active' : 'pending');
    }

    get step3Status() {
        return this.setupStatus?.hasUserAuthenticated ? 'completed' : (this.currentStep === 3 ? 'active' : 'pending');
    }

    get step4Status() {
        return this.setupStatus?.isConfigured ? 'completed' : 'pending';
    }

    get step1Class() {
        return `step-indicator ${this.step1Status}`;
    }

    get step2Class() {
        return `step-indicator ${this.step2Status}`;
    }

    get step3Class() {
        return `step-indicator ${this.step3Status}`;
    }

    get step4Class() {
        return `step-indicator ${this.step4Status}`;
    }

    get orgDomain() {
        return window.location.origin;
    }

    get callbackUrl() {
        return `${this.orgDomain}/services/authcallback/API_Version_Updater`;
    }

    get setupUrl() {
        return `${this.orgDomain}/lightning/setup/SetupOneHome/home`;
    }

    get appManagerUrl() {
        return `${this.orgDomain}/lightning/setup/NavigationMenus/home`;
    }

    get newConnectedAppUrl() {
        return `${this.orgDomain}/lightning/setup/ConnectedApplication/new`;
    }

    get namedCredentialsUrl() {
        return `${this.orgDomain}/lightning/setup/NamedCredential/home`;
    }

    get externalCredentialsUrl() {
        return `${this.orgDomain}/lightning/setup/ExternalCredentials/home`;
    }

    get permissionSetsUrl() {
        return `${this.orgDomain}/lightning/setup/PermSets/home`;
    }

    handleGoToStep(event) {
        const step = parseInt(event.target.dataset.step, 10);
        if (step && step >= 1 && step <= 4) {
            this.currentStep = step;
        }
    }

    handleOpenSetup(event) {
        const url = event.target.dataset.url;
        if (url) {
            window.open(url, '_blank');
        }
    }

    handleCopyText(event) {
        const text = event.target.dataset.text;
        if (text) {
            navigator.clipboard.writeText(text).then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Copied',
                    message: 'Text copied to clipboard',
                    variant: 'success'
                }));
            }).catch(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Copy Failed',
                    message: 'Please copy the text manually',
                    variant: 'warning'
                }));
            });
        }
    }
}
