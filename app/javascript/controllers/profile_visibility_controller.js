import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["checkbox", "content", "sections", "form", "menuItems"]

    connect() {
        this.updateVisibility()
    }

    async toggle(event) {
        const enabled = event.target.checked

        // Submit the form via Turbo
        const form = this.formTarget
        const formData = new FormData(form)

        try {
            await fetch(form.action, {
                method: 'PATCH',
                body: formData,
                headers: {
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
                    'Accept': 'text/vnd.turbo-stream.html'
                },
                credentials: 'same-origin'
            })

            // Update visibility immediately
            this.updateVisibility()
        } catch (error) {
            console.error('Error updating profile visibility:', error)
            // Revert checkbox on error
            event.target.checked = !enabled
        }
    }

    updateVisibility() {
        const enabled = this.checkboxTarget.checked

        // Toggle content visibility (URL box and buttons)
        if (this.hasContentTarget) {
            if (enabled) {
                this.contentTarget.classList.remove('hidden')
            } else {
                this.contentTarget.classList.add('hidden')
            }
        }

        // Toggle sections visibility (all profile sections)
        if (this.hasSectionsTarget) {
            if (enabled) {
                this.sectionsTarget.classList.remove('hidden')
            } else {
                this.sectionsTarget.classList.add('hidden')
            }
        }

        // Toggle menu items visibility
        if (this.hasMenuItemsTarget) {
            this.menuItemsTargets.forEach(item => {
                if (enabled) {
                    item.classList.remove('hidden')
                } else {
                    item.classList.add('hidden')
                }
            })
        }
    }
}
