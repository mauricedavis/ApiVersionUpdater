import { LightningElement, track } from "lwc";
import getCounts from "@salesforce/apex/ApiVersionWizardController.getCounts";

export default class ApiVersionWizardHost extends LightningElement {
  @track loading = false;
  @track error = "";
  @track threshold;
  @track target;
  @track excludeManaged = true;
  @track counts;

  get showResults() { return !!this.counts; }

  handleStartCheck = async (evt) => {
    this.error = "";
    this.counts = null;
    this.loading = true;

    const { threshold, target, excludeManaged } = evt.detail;
    this.threshold = threshold;
    this.target = target;
    this.excludeManaged = excludeManaged;

    try {
      this.counts = await getCounts({ threshold, target, excludeManaged });
    } catch (e) {
      this.error = e?.body?.message || e?.message || "Check failed.";
    } finally {
      this.loading = false;
    }
  };
}
