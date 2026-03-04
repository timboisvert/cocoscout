import { Controller } from "@hotwired/stimulus"

// Truncates long text with a fade overlay and "Read more" / "Show less" toggle.
// Usage:
//   <div data-controller="text-expand">
//     <div data-text-expand-target="content" class="overflow-hidden" style="max-height: 192px;">
//       Long content...
//     </div>
//     <div data-text-expand-target="fade" class="...gradient..."></div>
//     <button data-action="text-expand#toggle" data-text-expand-target="toggleBtn">Read more</button>
//   </div>
export default class extends Controller {
    static targets = ["content", "fade", "toggleBtn"]
    static values = { maxHeight: { type: Number, default: 192 } }

    connect() {
        // If content is shorter than the max height, hide the controls
        requestAnimationFrame(() => {
            if (this.contentTarget.scrollHeight <= this.maxHeightValue) {
                this.contentTarget.style.maxHeight = "none"
                if (this.hasFadeTarget) this.fadeTarget.classList.add("hidden")
                if (this.hasToggleBtnTarget) this.toggleBtnTarget.classList.add("hidden")
            }
        })
    }

    toggle() {
        const isCollapsed = this.contentTarget.style.maxHeight !== "none"

        if (isCollapsed) {
            this.contentTarget.style.maxHeight = "none"
            if (this.hasFadeTarget) this.fadeTarget.classList.add("hidden")
            if (this.hasToggleBtnTarget) this.toggleBtnTarget.textContent = "Show less"
        } else {
            this.contentTarget.style.maxHeight = `${this.maxHeightValue}px`
            if (this.hasFadeTarget) this.fadeTarget.classList.remove("hidden")
            if (this.hasToggleBtnTarget) this.toggleBtnTarget.textContent = "Read more"
        }
    }
}
