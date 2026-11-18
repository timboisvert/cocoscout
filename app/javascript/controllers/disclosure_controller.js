import { Controller } from "@hotwired/stimulus"

// Simple disclosure/accordion controller
// Usage:
//   <div data-controller="disclosure">
//     <button data-action="click->disclosure#toggle">Toggle</button>
//     <div data-disclosure-target="content" class="hidden">Content</div>
//   </div>
export default class extends Controller {
    // closedOnly / openOnly: pieces of the header that show in one state only
    // (a summary while closed, a tool once open).
    static targets = ["content", "icon", "closedOnly", "openOnly"]

    // For controls that sit inside the toggle (a button on the header row):
    // data-action="click->disclosure#keep:stop" keeps their click from toggling.
    keep() {}

    toggle() {
        const open = !this.contentTarget.classList.toggle("hidden")
        this.closedOnlyTargets.forEach((el) => el.classList.toggle("hidden", open))
        this.openOnlyTargets.forEach((el) => el.classList.toggle("hidden", !open))

        if (this.hasIconTarget) {
            // Rotate the icon when open (180 for down arrows, 90 for right arrows)
            if (this.contentTarget.classList.contains("hidden")) {
                this.iconTarget.classList.remove("rotate-180", "rotate-90")
            } else {
                // Use rotate-180 for down chevrons, rotate-90 for right chevrons
                this.iconTarget.classList.add("rotate-180")
            }
        }
    }
}
