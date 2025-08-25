import { LightningElement, api, track } from "lwc";
import getItems from "@salesforce/apex/ApiVersionWizardController.getItems";
import updateApiVersions from "@salesforce/apex/ApiVersionWizardController.updateApiVersions";

const COLS = [
  { label: "Type", fieldName: "type", sortable: true },
  { label: "Name", fieldName: "name", sortable: true },
  { label: "API Version", fieldName: "apiVersion", type: "number" },
  { label: "Namespace", fieldName: "namespacePrefix" }
];

export default class ApiVersionResults extends LightningElement {
  @api threshold;
  @api target;
  @api excludeManaged;
  @api pageSize = 50;

  @track rows = [];
  @track total = 0;
  @track pageNumber = 1;
  @track totalPages = 1;
  @track error = "";
  @track updateMessage = "";

  _selected = [];
  columns = COLS;

  connectedCallback() { this.fetch(); }

  get isPrevDisabled() { return this.pageNumber <= 1; }
  get isNextDisabled() { return this.pageNumber >= this.totalPages; }
  get updateDisabled() { return !this._selected.length; }

  async fetch() {
    this.error = "";
    try {
      const res = await getItems({
        threshold: this.threshold,
        excludeManaged: this.excludeManaged,
        pageNumber: this.pageNumber,
        pageSize: this.pageSize
      });
      this.rows = res.items;
      this.total = res.total;
      this.totalPages = Math.max(1, Math.ceil(this.total / this.pageSize));
    } catch (e) {
      this.error = e?.body?.message || e?.message || "Unknown error loading items.";
    }
  }

  async refreshAfterUpdate() {
    this.pageNumber = 1;
    await this.fetch();
  }

  handleSelection(evt) {
    this._selected = evt.detail.selectedRows || [];
  }

  async updateSelected() {
    this.error = "";
    this.updateMessage = "";
    if (!this._selected.length) return;
    try {
      const payload = this._selected.map(r => ({ id: r.id, type: r.type }));
      const res = await updateApiVersions({ target: this.target, items: payload });
      const ok = res.results.filter(r => r.success).length;
      const fail = res.results.length - ok;
      this.updateMessage = `Updated ${ok} item(s)` + (fail ? `, ${fail} failed` : "");
      await this.refreshAfterUpdate();
    } catch (e) {
      this.error = e?.body?.message || e?.message || "Update failed.";
    }
  }

  async nextPage() { if (!this.isNextDisabled) { this.pageNumber++; await this.fetch(); } }
  async prevPage() { if (!this.isPrevDisabled) { this.pageNumber--; await this.fetch(); } }
}
