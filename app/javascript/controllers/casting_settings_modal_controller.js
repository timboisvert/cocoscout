import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "modal",
        "castingEnabledCheckbox",
        "castingSourceOverrideCheckbox",
        "castingSourceOptions",
        "castingSourceSelect",
        "signupBasedCastingCheckbox",
        "signupBasedCastingInfo",
        "attendanceCheckbox"
    ]

    static values = {
        showId: Number,
        productionId: Number,
        updateUrl: String,
        toggleSignupBasedCastingUrl: String,
        toggleAttendanceUrl: String
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

    async toggleSignupBasedCasting() {
        const enabled = this.signupBasedCastingCheckboxTarget.checked

        if (this.hasToggleSignupBasedCastingUrlValue) {
            try {
                const response = await fetch(this.toggleSignupBasedCastingUrlValue, {
                    method: "POST",
                    headers: {
                        "Accept": "application/json",
                        "Content-Type": "application/json",
                        "X-CSRF-Token": this.csrfToken
                    },
                    body: JSON.stringify({ enabled: enabled })
                })

                if (response.ok) {
                    // Show/hide the info section
                    if (this.hasSignupBasedCastingInfoTarget) {
                        if (enabled) {
                            this.signupBasedCastingInfoTarget.classList.remove("hidden")
                        } else {
                            this.signupBasedCastingInfoTarget.classList.add("hidden")
                        }
                    }
                    // Reload the page to show updated attendee role
                    window.location.reload()
                } else {
                    // Revert the checkbox on error
                    this.signupBasedCastingCheckboxTarget.checked = !enabled
                    console.error("Failed to toggle signup-based casting")
                }
            } catch (error) {
                this.signupBasedCastingCheckboxTarget.checked = !enabled
                console.error("Failed to toggle signup-based casting:", error)
            }
        }
    }

    async toggleAttendance() {
        if (this.hasToggleAttendanceUrlValue) {
            try {
                const response = await fetch(this.toggleAttendanceUrlValue, {
                    method: "POST",
                    headers: {
                        "Accept": "application/json",
                        "Content-Type": "application/json",
                        "X-CSRF-Token": this.csrfToken
                    }
                })

                if (!response.ok) {
                    console.error("Failed to toggle attendance")
                }
            } catch (error) {
                console.error("Failed to toggle attendance:", error)
            }
        }
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
