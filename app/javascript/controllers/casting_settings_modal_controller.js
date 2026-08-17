import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "modal",
        "castingEnabledCheckbox",
        "castingSourceOverrideCheckbox",
        "castingSourceOptions",
        "castingSourceSelect",
        "castingModeOverrideCheckbox",
        "castingModeOptions",
        "castingModeOption",
        "castingModeRadio"
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

    // Casting style (roles vs acts) override — mirrors the casting source
    // override: nil/empty means "inherit from production". The board is drawn
    // entirely differently per mode, so a change reloads the page.
    async toggleCastingModeOverride() {
        const enabled = this.castingModeOverrideCheckboxTarget.checked
        if (enabled) {
            this.castingModeOptionsTarget.classList.remove("hidden")
        } else {
            this.castingModeOptionsTarget.classList.add("hidden")
            // Clear the casting style override (empty = inherit)
            const ok = await this.updateShow({ casting_mode: "" })
            if (ok) window.location.reload()
        }
    }

    async updateCastingMode() {
        const checked = this.castingModeRadioTargets.find(r => r.checked)
        if (!checked) return

        this.castingModeOptionTargets.forEach(option => {
            const selected = option.contains(checked)
            option.classList.toggle("border-pink-500", selected)
            option.classList.toggle("bg-pink-50", selected)
            option.classList.toggle("border-gray-200", !selected)
        })

        const ok = await this.updateShow({ casting_mode: checked.value })
        if (ok) window.location.reload()
    }

    async updateShow(params) {
        if (!this.hasUpdateUrlValue) return false

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

            // A successful update answers with a redirect to the show page
            // (which fetch follows), so count a redirected response as saved.
            if (!response.ok && !response.redirected) {
                console.error("Failed to update show")
                return false
            }
            return true
        } catch (error) {
            console.error("Failed to update show:", error)
            return false
        }
    }
}
