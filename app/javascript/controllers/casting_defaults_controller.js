import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["signupBasedCastingCheckbox"]
    static values = { updateUrl: String }

    get csrfToken() {
        return document.querySelector('meta[name="csrf-token"]')?.content
    }

    async updateSignupBasedCasting() {
        const enabled = this.signupBasedCastingCheckboxTarget.checked
        await this.updateProduction({ default_signup_based_casting: enabled })
    }

    async updateProduction(params) {
        if (!this.hasUpdateUrlValue) return

        try {
            const response = await fetch(this.updateUrlValue, {
                method: "PATCH",
                headers: {
                    "Accept": "text/vnd.turbo-stream.html, application/json",
                    "Content-Type": "application/json",
                    "X-CSRF-Token": this.csrfToken
                },
                body: JSON.stringify({ production: params })
            })

            if (!response.ok) {
                console.error("Failed to update production settings")
            }
        } catch (error) {
            console.error("Failed to update production settings:", error)
        }
    }
}
