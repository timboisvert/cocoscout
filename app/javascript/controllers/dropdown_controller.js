import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["menu"]

    connect() {
        this.boundHide = this.hide.bind(this)
        document.addEventListener("click", this.boundHide)
    }

    disconnect() {
        document.removeEventListener("click", this.boundHide)
    }

    toggle(event) {
        event.stopPropagation()

        // Close all other dropdowns first
        document.querySelectorAll('[data-controller="dropdown"]').forEach(dropdown => {
            if (dropdown !== this.element) {
                const menu = dropdown.querySelector('[data-dropdown-target="menu"]')
                if (menu) {
                    menu.classList.add("hidden")
                }
            }
        })

        // Toggle this dropdown
        const opening = this.menuTarget.classList.contains("hidden")
        this.menuTarget.classList.toggle("hidden")
        if (opening) this.fitToViewport()
    }

    // Menus anchor to their trigger's left edge, so a wide menu opened from a
    // control near the right of the screen runs off it. Once open, measure and
    // slide it back so it always fits left-to-right (a translate, so it works
    // whether the menu is anchored left or right and never touches layout).
    fitToViewport() {
        const menu = this.menuTarget
        menu.style.transform = ""
        const margin = 8
        const viewportWidth = document.documentElement.clientWidth
        const rect = menu.getBoundingClientRect()
        let dx = 0
        if (rect.right > viewportWidth - margin) dx = (viewportWidth - margin) - rect.right
        if (rect.left + dx < margin) dx = margin - rect.left
        if (dx !== 0) menu.style.transform = `translateX(${Math.round(dx)}px)`
    }

    close() {
        this.menuTarget.classList.add("hidden")
    }

    hide(event) {
        if (!this.element.contains(event.target)) {
            this.menuTarget.classList.add("hidden")
        }
    }
}
