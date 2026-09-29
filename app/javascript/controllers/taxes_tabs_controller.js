import { Controller } from "@hotwired/stimulus"

// Tabs for Staffing → Taxes (W-9s / 1099s). Same shape as the staff-edit tabs,
// but standalone so opening one tab doesn't need to know about form footers.
// A #tab in the URL opens that tab (used by controller redirects that want to
// land the user back on the right one).
export default class extends Controller {
    static targets = ["tab", "panel"]

    connect() {
        const fromHash = window.location.hash.slice(1)
        const known = this.tabTargets.some(t => t.dataset.tab === fromHash)
        this.switchTo(known ? fromHash : (this.tabTargets[0]?.dataset.tab || "w9s"))
    }

    switch(event) {
        if (event) event.preventDefault()
        const key = event.currentTarget.dataset.tab
        this.switchTo(key)
        // Reflect in the URL without a reload so a page refresh stays on the tab.
        history.replaceState(null, "", `#${key}`)
    }

    switchTo(key) {
        this.tabTargets.forEach(t => {
            const active = t.dataset.tab === key
            t.classList.toggle("border-pink-500", active)
            t.classList.toggle("text-pink-600", active)
            t.classList.toggle("border-transparent", !active)
            t.classList.toggle("text-gray-500", !active)
        })
        this.panelTargets.forEach(p => p.classList.toggle("hidden", p.dataset.panel !== key))
    }
}
