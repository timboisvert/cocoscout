import { Controller } from "@hotwired/stimulus"

// The staff W-9 form: shows the LLC / "Other" follow-up fields only for the
// classification that needs them, and relabels the tax ID field for SSN vs EIN.
export default class extends Controller {
    static targets = ["classification", "llc", "other", "tinLabel", "tin"]

    connect() {
        this.update()
    }

    update() {
        const classification = this.hasClassificationTarget ? this.classificationTarget.value : ""
        if (this.hasLlcTarget) this.llcTarget.classList.toggle("hidden", classification !== "llc")
        if (this.hasOtherTarget) this.otherTarget.classList.toggle("hidden", classification !== "other")

        const tinType = this.element.querySelector("input[name='w9[tin_type]']:checked")?.value || "ssn"
        const ein = tinType === "ein"
        if (this.hasTinLabelTarget) this.tinLabelTarget.textContent = ein ? "Employer identification number (EIN)" : "Social Security number"
        if (this.hasTinTarget) this.tinTarget.placeholder = ein ? "12-3456789" : "123-45-6789"
    }
}
