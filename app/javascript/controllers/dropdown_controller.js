import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["menu"]
    // fixed: the menu floats over the page at its trigger instead of hanging
    // inside it, for menus inside a box that scrolls or clips (a table row in
    // an overflow-x-auto card), which would otherwise stretch and scroll the
    // box. It flips up when there's no room below and closes on scroll.
    static values = { fixed: Boolean }

    connect() {
        this.boundHide = this.hide.bind(this)
        document.addEventListener("click", this.boundHide)
        if (this.fixedValue) {
            this.boundClose = this.close.bind(this)
            window.addEventListener("scroll", this.boundClose, true)
            window.addEventListener("resize", this.boundClose)
        }
    }

    disconnect() {
        document.removeEventListener("click", this.boundHide)
        if (this.boundClose) {
            window.removeEventListener("scroll", this.boundClose, true)
            window.removeEventListener("resize", this.boundClose)
        }
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
        if (opening) {
            if (this.fixedValue) this.placeAt(event.currentTarget)
            this.fitToViewport()
        }
    }

    // Pin the open menu to the viewport, right-aligned under its trigger (or
    // above it when it would run off the bottom).
    placeAt(trigger) {
        const menu = this.menuTarget
        const gap = 4
        const margin = 8
        const r = trigger.getBoundingClientRect()
        menu.style.position = "fixed"
        menu.style.left = "auto"
        menu.style.right = `${Math.round(document.documentElement.clientWidth - r.right)}px`
        menu.style.top = `${Math.round(r.bottom + gap)}px`
        const height = menu.offsetHeight
        if (r.bottom + gap + height > window.innerHeight - margin && r.top - gap - height >= margin) {
            menu.style.top = `${Math.round(r.top - gap - height)}px`
        }
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
