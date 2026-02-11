import { Controller } from "@hotwired/stimulus"

// Controls the sender identity dropdown in the reply form
export default class extends Controller {
    static targets = ["input", "button", "label", "icon"]

    select(event) {
        const value = event.currentTarget.dataset.value
        const label = event.currentTarget.dataset.label

        // Update hidden input
        if (this.hasInputTarget) {
            this.inputTarget.value = value
        }

        // Update button label
        this.labelTarget.textContent = label

        // Copy the icon/image from the clicked option
        // Find the icon element in the clicked button (first child that's an img or div)
        const clickedOption = event.currentTarget
        const sourceIcon = clickedOption.querySelector('img, div:first-child')
        if (sourceIcon && this.hasIconTarget) {
            // Clone the icon element and replace the current icon's content
            const clonedIcon = sourceIcon.cloneNode(true)
            this.iconTarget.innerHTML = ''
            this.iconTarget.appendChild(clonedIcon)
        }
    }
}
