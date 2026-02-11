import { Controller } from "@hotwired/stimulus"

// Controls the sender identity dropdown in the reply form
export default class extends Controller {
    static targets = ["input", "button", "label", "icon"]

    connect() {
        console.log("[reply-sender] Connected")
        console.log("[reply-sender] Has input target:", this.hasInputTarget)
        if (this.hasInputTarget) {
            console.log("[reply-sender] Input value:", this.inputTarget.value)
        }
    }

    select(event) {
        const value = event.currentTarget.dataset.value
        const label = event.currentTarget.dataset.label

        console.log("[reply-sender] Selecting:", value, label)
        console.log("[reply-sender] Has input target:", this.hasInputTarget)

        // Update hidden input
        if (this.hasInputTarget) {
            this.inputTarget.value = value
            console.log("[reply-sender] Updated input to:", this.inputTarget.value)
        } else {
            console.error("[reply-sender] No input target found!")
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
