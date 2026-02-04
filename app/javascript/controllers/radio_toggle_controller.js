import { Controller } from "@hotwired/stimulus"

/**
 * Radio Toggle Controller
 *
 * Shows/hides a target element based on radio button selection.
 * Also toggles card styling for visual selection feedback.
 *
 * Usage:
 *   <div data-controller="radio-toggle" data-radio-toggle-show-value="yes">
 *     <label>
 *       <div data-radio-toggle-target="card" data-value="yes">
 *         <input type="radio" name="option" value="yes" checked
 *                data-action="change->radio-toggle#update">
 *         <div data-radio-toggle-target="content">
 *           Content shown when "yes" is selected
 *         </div>
 *       </div>
 *     </label>
 *     <label>
 *       <div data-radio-toggle-target="card" data-value="no">
 *         <input type="radio" name="option" value="no"
 *                data-action="change->radio-toggle#update">
 *       </div>
 *     </label>
 *   </div>
 */
export default class extends Controller {
    static targets = ["content", "card"]
    static values = {
        show: { type: String, default: "yes" } // Value that shows the content
    }

    connect() {
        // Set initial state based on checked radio
        this.update()
    }

    update() {
        const checkedRadio = this.element.querySelector(`input[type="radio"][name]:checked`)
        if (!checkedRadio) return

        // Toggle content visibility
        if (this.hasContentTarget) {
            if (checkedRadio.value === this.showValue) {
                this.contentTarget.classList.remove("hidden")
            } else {
                this.contentTarget.classList.add("hidden")
            }
        }

        // Toggle card styling
        if (this.hasCardTarget) {
            this.cardTargets.forEach(card => {
                const cardValue = card.dataset.value
                if (cardValue === checkedRadio.value) {
                    // Selected state
                    card.classList.remove("border-gray-200", "bg-gray-50")
                    card.classList.add("border-pink-500", "bg-pink-50")
                } else {
                    // Unselected state
                    card.classList.remove("border-pink-500", "bg-pink-50")
                    card.classList.add("border-gray-200", "bg-gray-50")
                }
            })
        }
    }
}
