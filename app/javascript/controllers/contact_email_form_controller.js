import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["productionSelect", "subjectPrefix"]

    updateSubjectPrefix() {
        if (!this.hasProductionSelectTarget || !this.hasSubjectPrefixTarget) return

        const selectedOption = this.productionSelectTarget.selectedOptions[0]
        const productionName = selectedOption?.dataset.name

        if (productionName) {
            this.subjectPrefixTarget.textContent = `[${productionName}]`
        }
    }
}
