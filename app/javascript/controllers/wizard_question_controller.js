import { Controller } from "@hotwired/stimulus"

// Shows/hides the Options field on the wizard's Add Question modal
// based on the selected question type.
export default class extends Controller {
    static targets = ["typeSelect", "optionsSection"]
    static values = { needsOptionsKeys: Array }

    connect() {
        this.update()
    }

    typeChanged() {
        this.update()
    }

    update() {
        if (!this.hasTypeSelectTarget || !this.hasOptionsSectionTarget) return
        const key = this.typeSelectTarget.value
        if (this.needsOptionsKeysValue.includes(key)) {
            this.optionsSectionTarget.classList.remove("hidden")
        } else {
            this.optionsSectionTarget.classList.add("hidden")
        }
    }
}
