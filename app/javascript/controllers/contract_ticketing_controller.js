import { Controller } from "@hotwired/stimulus"

// Manages the list of ticket tiers (name + price) and the optional discount code,
// serializing everything into a hidden JSON field for the wizard form submit.
export default class extends Controller {
    static targets = [
        "tierName", "tierPrice", "list", "ticketingJson",
        "discountCode", "discountAmount", "discountType",
        "specificTiers", "specificTiersWrapper"
    ]
    static values = { existing: Object }

    connect() {
        const existing = this.existingValue || {}
        this.tiers = Array.isArray(existing.tiers) ? existing.tiers : []
        this.discount = existing.discount || {}
        this.renderList()
        this.toggleAppliesTo()
        this.serialize()
    }

    addTier() {
        const name = this.tierNameTarget.value.trim()
        const price = parseFloat(this.tierPriceTarget.value)

        if (!name) {
            alert("Please enter a tier name")
            return
        }
        if (isNaN(price) || price < 0) {
            alert("Please enter a valid price")
            return
        }
        if (this.tiers.some(t => t.name.toLowerCase() === name.toLowerCase())) {
            alert("This tier name is already added")
            return
        }

        this.tiers.push({ name, price })
        this.tierNameTarget.value = ""
        this.tierPriceTarget.value = ""
        this.renderList()
        this.renderSpecificTiers()
        this.serialize()
    }

    removeTier(event) {
        const index = parseInt(event.currentTarget.dataset.index)
        this.tiers.splice(index, 1)
        this.renderList()
        this.renderSpecificTiers()
        this.serialize()
    }

    get appliesTo() {
        const checked = this.element.querySelector('input[name="discount_applies_to"]:checked')
        return checked ? checked.value : "all"
    }

    toggleAppliesTo() {
        if (!this.hasSpecificTiersWrapperTarget) return
        if (this.appliesTo === "specific") {
            this.specificTiersWrapperTarget.classList.remove("hidden")
            this.renderSpecificTiers()
        } else {
            this.specificTiersWrapperTarget.classList.add("hidden")
        }
        this.serialize()
    }

    renderList() {
        if (this.tiers.length === 0) {
            this.listTarget.innerHTML = `<p class="text-gray-500 text-sm">No ticket tiers added yet.</p>`
            return
        }

        this.listTarget.innerHTML = `
      <div class="space-y-2">
        ${this.tiers.map((tier, index) => `
          <div class="flex items-center justify-between p-2 bg-gray-50 rounded-lg">
            <span class="text-sm text-gray-900">${this.escape(tier.name)}</span>
            <div class="flex items-center gap-3">
              <span class="text-sm font-medium text-gray-900">$${Number(tier.price).toFixed(2)}</span>
              <button type="button" data-action="click->contract-ticketing#removeTier" data-index="${index}" class="text-red-500 hover:text-red-700">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          </div>
        `).join("")}
      </div>
    `
    }

    renderSpecificTiers() {
        if (!this.hasSpecificTiersTarget) return
        const selected = this.discount.tier_names || []

        if (this.tiers.length === 0) {
            this.specificTiersTarget.innerHTML = `<p class="text-gray-500 text-sm">Add tiers above first.</p>`
            return
        }

        this.specificTiersTarget.innerHTML = this.tiers.map(tier => `
      <label class="flex items-center gap-2 py-1">
        <input type="checkbox" value="${this.escape(tier.name)}"
               ${selected.includes(tier.name) ? "checked" : ""}
               data-action="change->contract-ticketing#serialize"
               class="h-4 w-4 text-pink-600 border-gray-300 rounded focus:ring-pink-500 accent-pink-500">
        <span class="text-sm text-gray-900">${this.escape(tier.name)}</span>
      </label>
    `).join("")
    }

    serialize() {
        const tierNames = this.hasSpecificTiersTarget
            ? Array.from(this.specificTiersTarget.querySelectorAll('input[type="checkbox"]:checked')).map(c => c.value)
            : (this.discount.tier_names || [])

        this.discount = {
            code: this.discountCodeTarget.value.trim(),
            amount: this.discountAmountTarget.value ? parseFloat(this.discountAmountTarget.value) : null,
            amount_type: this.discountTypeTarget.value,
            applies_to: this.appliesTo,
            tier_names: this.appliesTo === "specific" ? tierNames : []
        }

        this.ticketingJsonTarget.value = JSON.stringify({ tiers: this.tiers, discount: this.discount })
    }

    escape(str) {
        const div = document.createElement("div")
        div.textContent = str
        return div.innerHTML
    }
}
