import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "modal",
        "castingEnabledCheckbox",
        "castingSourceOverrideCheckbox",
        "castingSourceOptions",
        "castingSourceSelect"
    ]

    static values = {
        showId: Number,
        productionId: Number,
        updateUrl: String
    }

    connect() {
        this.boundHandleKeydown = this.handleKeydown.bind(this)
        document.addEventListener("keydown", this.boundHandleKeydown)
    }

    disconnect() {
        document.removeEventListener("keydown", this.boundHandleKeydown)
    }

    handleKeydown(event) {
        if (event.key === "Escape" && !this.modalTarget.classList.contains("hidden")) {
            this.closeModal()
        }
    }

    openModal(event) {
        if (event) event.preventDefault()
        this.modalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")
    }

    closeModal() {
        this.modalTarget.classList.add("hidden")
        document.body.classList.remove("overflow-hidden")
        // Reload page to reflect any changes made
        window.location.reload()
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    get csrfToken() {
        return document.querySelector('meta[name="csrf-token"]')?.content
    }

    async updateCastingEnabled() {
        const enabled = this.castingEnabledCheckboxTarget.checked
        await this.updateShow({ casting_enabled: enabled })
    }

    toggleCastingSourceOverride() {
        const enabled = this.castingSourceOverrideCheckboxTarget.checked
        if (enabled) {
            this.castingSourceOptionsTarget.classList.remove("hidden")
        } else {
            this.castingSourceOptionsTarget.classList.add("hidden")
            // Clear the casting source override
            this.updateShow({ casting_source: null })
        }
    }

    async updateCastingSource() {
        const source = this.castingSourceSelectTarget.value
        await this.updateShow({ casting_source: source })
    }

    async updateShow(params) {
        if (!this.hasUpdateUrlValue) return

        try {
            const response = await fetch(this.updateUrlValue, {
                method: "PATCH",
                headers: {
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "X-CSRF-Token": this.csrfToken
                },
                body: JSON.stringify({ show: params })
            })

            if (!response.ok) {
                console.error("Failed to update show")
            }
        } catch (error) {
            console.error("Failed to update show:", error)
        }
    }
}
