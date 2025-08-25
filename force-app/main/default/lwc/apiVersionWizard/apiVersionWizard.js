import { LightningElement, track } from "lwc";
const DEFAULT_THRESHOLD = 50.0;
const DEFAULT_TARGET = 63.0;
const QUICK_THRESHOLDS = ["45.0","50.0","55.0","60.0"];
const QUICK_TARGETS    = ["60.0","61.0","62.0","63.0"];

export default class ApiVersionWizard extends LightningElement {
  @track threshold = DEFAULT_THRESHOLD;
  @track target = DEFAULT_TARGET;
  @track excludeManaged = true;
  @track error = "";

  quickThresholds = QUICK_THRESHOLDS;
  quickTargets = QUICK_TARGETS;

  get isSubmitDisabled() { return !!this.error || !this.threshold || !this.target; }
  connectedCallback() { this.validate(); }

  handleThresholdChange = (e) => { this.threshold = this.normalizeNumber(e.target.value); this.validate(); };
  handleTargetChange    = (e) => { this.target    = this.normalizeNumber(e.target.value); this.validate(); };
  handlePickThreshold   = (e) => { this.threshold = this.normalizeNumber(e.target.label); this.validate(); };
  handlePickTarget      = (e) => { this.target    = this.normalizeNumber(e.target.label); this.validate(); };
  handleExcludeManagedChange = (e) => { this.excludeManaged = e.target.checked; };

  handleReset = () => {
    this.threshold = DEFAULT_THRESHOLD;
    this.target = DEFAULT_TARGET;
    this.excludeManaged = true;
    this.error = "";
    this.template.querySelectorAll("lightning-input").forEach((i) => i.reportValidity());
  };

  handleSubmit = () => {
    this.validate();
    if (this.error) return;
    const payload = { threshold: this.threshold, target: this.target, excludeManaged: this.excludeManaged };
    this.dispatchEvent(new CustomEvent("startcheck", { detail: payload, bubbles: true, composed: true }));
  };

  validate() {
    this.error = "";
    const t = Number(this.threshold), v = Number(this.target);
    if (Number.isNaN(t) || Number.isNaN(v)) { this.error = "Both values must be numbers."; return; }
    if (t <= 0 || v <= 0) { this.error = "Values must be positive numbers."; return; }
    if (t >= v) { this.error = "Threshold must be less than the target version."; return; }
    if (t > 200 || v > 200) { this.error = "Please use values below 200."; return; }
  }

  normalizeNumber(value) {
    const n = Number(value);
    if (Number.isNaN(n)) return null;
    return Number(n.toFixed(1));
  }
}
