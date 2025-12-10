import { Controller } from "@hotwired/stimulus"

// Simple disclosure/accordion controller
// Usage:
//   <div data-controller="disclosure">
//     <button data-action="click->disclosure#toggle">Toggle</button>
//     <div data-disclosure-target="content" class="hidden">Content</div>
//   </div>
export default class extends Controller {
    static targets = ["content", "icon"]

    toggle() {
        this.contentTarget.classList.toggle("hidden")

        if (this.hasIconTarget) {
            // Rotate the icon when open
            if (this.contentTarget.classList.contains("hidden")) {
                this.iconTarget.classList.remove("rotate-90")
            } else {
                this.iconTarget.classList.add("rotate-90")
            }
        }
    }
}
