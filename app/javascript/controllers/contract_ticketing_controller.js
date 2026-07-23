import { Controller } from "@hotwired/stimulus"

// Ticket tiers and discount codes, each managed as a list you add to through a
// modal. Everything serializes into a hidden JSON field for the wizard submit:
//   { tiers: [{name, price}], discounts: [{code, amount, amount_type, applies_to, tier_names}] }
export default class extends Controller {
    static targets = [
        "tierList", "tierModal", "tierName", "tierPrice", "tierError",
        "discountList", "discountModal", "discountError",
        "discountCode", "discountAmount", "discountType",
        "discountTierWrapper", "discountTiers",
        "ticketingJson"
    ]
    static values = { existing: Object }

    connect() {
        const existing = this.existingValue || {}
        this.tiers = Array.isArray(existing.tiers) ? existing.tiers : []
        // Accept both the new list and a single legacy discount.
        this.discounts = Array.isArray(existing.discounts)
            ? existing.discounts
            : (existing.discount && existing.discount.code ? [existing.discount] : [])
        this.renderTiers()
        this.renderDiscounts()
        this.serialize()
    }

    // --- Ticket tiers -----------------------------------------------------

    openTierModal() {
        this.tierNameTarget.value = ""
        this.tierPriceTarget.value = ""
        this.hideError(this.tierErrorTarget)
        this.showModal(this.tierModalTarget)
        this.tierNameTarget.focus()
    }

    closeTierModal() { this.hideModal(this.tierModalTarget) }

    addTier() {
        const name = this.tierNameTarget.value.trim()
        const price = parseFloat(this.tierPriceTarget.value)

        if (!name) return this.showError(this.tierErrorTarget, "Give the tier a name.")
        if (isNaN(price) || price < 0) return this.showError(this.tierErrorTarget, "Enter a price of zero or more.")
        if (this.tiers.some(t => t.name.toLowerCase() === name.toLowerCase())) {
            return this.showError(this.tierErrorTarget, "You already have a tier with that name.")
        }

        this.tiers.push({ name, price })
        this.closeTierModal()
        this.renderTiers()
        this.serialize()
    }

    removeTier(event) {
        const index = parseInt(event.currentTarget.dataset.index)
        const removed = this.tiers.splice(index, 1)[0]
        // Drop the removed tier from any discount that named it.
        if (removed) {
            this.discounts.forEach(d => {
                if (Array.isArray(d.tier_names)) {
                    d.tier_names = d.tier_names.filter(n => n !== removed.name)
                }
            })
        }
        this.renderTiers()
        this.renderDiscounts()
        this.serialize()
    }

    renderTiers() {
        if (this.tiers.length === 0) {
            this.tierListTarget.innerHTML = this.emptyBox("No ticket tiers yet.", "Add the prices people can buy at.")
            return
        }
        this.tierListTarget.innerHTML = this.tiers.map((tier, index) => `
      <div class="flex items-center justify-between gap-3 p-4 bg-white rounded-xl border border-gray-200 shadow-sm">
        <span class="font-medium text-gray-900">${this.escape(tier.name)}</span>
        <div class="flex items-center gap-3">
          <span class="font-semibold text-gray-900">$${Number(tier.price).toFixed(2)}</span>
          <button type="button" data-action="click->contract-ticketing#removeTier" data-index="${index}" class="p-1 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition-colors" aria-label="Remove tier">
            ${this.xIcon()}
          </button>
        </div>
      </div>
    `).join("")
    }

    // --- Discount codes ---------------------------------------------------

    openDiscountModal() {
        this.discountCodeTarget.value = ""
        this.discountAmountTarget.value = ""
        this.discountTypeTarget.value = "percent"
        this.hideError(this.discountErrorTarget)
        this.setDiscountAppliesTo("all")
        this.renderDiscountTierChoices([])
        this.showModal(this.discountModalTarget)
        this.discountCodeTarget.focus()
    }

    closeDiscountModal() { this.hideModal(this.discountModalTarget) }

    // Show/hide the tier checkboxes as the applies-to choice changes.
    onDiscountAppliesToChange() {
        const specific = this.discountAppliesTo === "specific"
        this.discountTierWrapperTarget.classList.toggle("hidden", !specific)
    }

    addDiscount() {
        const code = this.discountCodeTarget.value.trim()
        const amount = parseFloat(this.discountAmountTarget.value)

        if (!code) return this.showError(this.discountErrorTarget, "Enter a code, like FRIENDS.")
        if (isNaN(amount) || amount <= 0) return this.showError(this.discountErrorTarget, "Enter how much comes off.")
        if (this.discounts.some(d => (d.code || "").toLowerCase() === code.toLowerCase())) {
            return this.showError(this.discountErrorTarget, "You already have that code.")
        }

        const appliesTo = this.discountAppliesTo
        const tierNames = appliesTo === "specific"
            ? Array.from(this.discountTiersTarget.querySelectorAll('input[type="checkbox"]:checked')).map(c => c.value)
            : []

        this.discounts.push({
            code,
            amount,
            amount_type: this.discountTypeTarget.value,
            applies_to: appliesTo,
            tier_names: tierNames
        })
        this.closeDiscountModal()
        this.renderDiscounts()
        this.serialize()
    }

    removeDiscount(event) {
        const index = parseInt(event.currentTarget.dataset.index)
        this.discounts.splice(index, 1)
        this.renderDiscounts()
        this.serialize()
    }

    renderDiscounts() {
        if (this.discounts.length === 0) {
            this.discountListTarget.innerHTML = this.emptyBox("No discount codes.", "Add one if you want to offer a code at checkout.")
            return
        }
        this.discountListTarget.innerHTML = this.discounts.map((d, index) => {
            const off = d.amount_type === "percent" ? `${d.amount}% off` : `$${Number(d.amount).toFixed(2)} off`
            const scope = d.applies_to === "specific" && (d.tier_names || []).length
                ? (d.tier_names || []).join(", ")
                : "all tickets"
            return `
      <div class="flex items-center justify-between gap-3 p-4 bg-white rounded-xl border border-gray-200 shadow-sm">
        <div class="min-w-0">
          <div class="font-medium text-gray-900">${this.escape(d.code)}</div>
          <div class="text-sm text-gray-500">${off} · ${this.escape(scope)}</div>
        </div>
        <button type="button" data-action="click->contract-ticketing#removeDiscount" data-index="${index}" class="p-1 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition-colors" aria-label="Remove code">
          ${this.xIcon()}
        </button>
      </div>
    `
        }).join("")
    }

    renderDiscountTierChoices(selected) {
        if (!this.hasDiscountTiersTarget) return
        if (this.tiers.length === 0) {
            this.discountTiersTarget.innerHTML = `<p class="text-sm text-gray-500">Add ticket tiers first to limit a code to some of them.</p>`
            return
        }
        this.discountTiersTarget.innerHTML = this.tiers.map(tier => `
      <label class="flex items-center gap-2 py-1">
        <input type="checkbox" value="${this.escape(tier.name)}" ${selected.includes(tier.name) ? "checked" : ""}
               class="h-4 w-4 text-pink-600 border-gray-300 rounded focus:ring-pink-500 accent-pink-500">
        <span class="text-sm text-gray-900">${this.escape(tier.name)}</span>
      </label>
    `).join("")
    }

    get discountAppliesTo() {
        const checked = this.discountModalTarget.querySelector('input[name="discount_applies_to"]:checked')
        return checked ? checked.value : "all"
    }

    setDiscountAppliesTo(value) {
        const radio = this.discountModalTarget.querySelector(`input[name="discount_applies_to"][value="${value}"]`)
        if (radio) radio.checked = true
        this.discountTierWrapperTarget.classList.toggle("hidden", value !== "specific")
    }

    // --- Shared -----------------------------------------------------------

    serialize() {
        // Keep a single `discount` alongside `discounts` so older readers that
        // expect one code still see the first.
        this.ticketingJsonTarget.value = JSON.stringify({
            tiers: this.tiers,
            discounts: this.discounts,
            discount: this.discounts[0] || {}
        })
    }

    emptyBox(title, hint) {
        return `
      <div class="text-center py-8 bg-gray-50 rounded-xl border-2 border-dashed border-gray-200">
        <p class="text-gray-500 text-sm">${title}</p>
        <p class="text-gray-400 text-xs mt-1">${hint}</p>
      </div>
    `
    }

    xIcon() {
        return `<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>`
    }

    showModal(el) { el.classList.remove("hidden"); document.body.classList.add("overflow-hidden") }
    hideModal(el) { el.classList.add("hidden"); document.body.classList.remove("overflow-hidden") }
    showError(el, msg) { el.textContent = msg; el.classList.remove("hidden") }
    hideError(el) { el.classList.add("hidden") }

    escape(str) {
        const div = document.createElement("div")
        div.textContent = str
        return div.innerHTML
    }
}
