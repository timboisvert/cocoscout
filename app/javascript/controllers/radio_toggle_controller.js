import { Controller } from "@hotwired/stimulus"

/**
 * Radio Toggle Controller
 *
 * Shows/hides a target element based on radio button selection.
 *
 * Usage:
 *   <div data-controller="radio-toggle">
 *     <input type="radio" name="option" value="yes" checked
 *            data-action="change->radio-toggle#update"
 *            data-radio-toggle-show-value="yes">
 *     <input type="radio" name="option" value="no"
 *            data-action="change->radio-toggle#update">
 *     <div data-radio-toggle-target="content">
 *       Content shown when "yes" is selected
 *     </div>
 *   </div>
 */
export default class extends Controller {
    static targets = ["content"]
    static values = {
        show: { type: String, default: "yes" } // Value that shows the content
    }

    connect() {
        // Set initial state based on checked radio
        this.update()
    }

    update() {
        const checkedRadio = this.element.querySelector(`input[type="radio"][name]:checked`)
        if (!checkedRadio || !this.hasContentTarget) return

        if (checkedRadio.value === this.showValue) {
            this.contentTarget.classList.remove("hidden")
        } else {
            this.contentTarget.classList.add("hidden")
        }
    }
}
