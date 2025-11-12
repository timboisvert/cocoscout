import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["menu"]

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
        this.menuTarget.classList.toggle("hidden")
    }

    hide(event) {
        if (!this.element.contains(event.target)) {
            this.menuTarget.classList.add("hidden")
        }
    }
}
