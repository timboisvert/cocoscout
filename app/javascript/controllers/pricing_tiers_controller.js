import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["container", "tier", "template"]

    addTier() {
        const index = this.tierTargets.length
        const template = this.templateTarget.innerHTML
        const newTier = template.replace(/INDEX/g, index)

        this.containerTarget.insertAdjacentHTML("beforeend", newTier)
        this.updateRemoveButtons()
    }

    removeTier(event) {
        const tierElement = event.target.closest("[data-pricing-tiers-target='tier']")
        if (tierElement && this.tierTargets.length > 1) {
            tierElement.remove()
            this.reindexTiers()
            this.updateRemoveButtons()
        }
    }

    reindexTiers() {
        this.tierTargets.forEach((tier, index) => {
            const inputs = tier.querySelectorAll("input")
            inputs.forEach((input) => {
                const name = input.getAttribute("name")
                if (name) {
                    input.setAttribute("name", name.replace(/pricing_tiers\[\d+\]/, `pricing_tiers[${index}]`))
                }
            })
        })
    }

    updateRemoveButtons() {
        const buttons = this.containerTarget.querySelectorAll("[data-action='click->pricing-tiers#removeTier']")
        buttons.forEach((button) => {
            if (this.tierTargets.length <= 1) {
                button.classList.add("invisible")
            } else {
                button.classList.remove("invisible")
            }
        })
    }
}
