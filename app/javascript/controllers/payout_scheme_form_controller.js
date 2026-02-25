import { Controller } from "@hotwired/stimulus"

// Manages the payout scheme form, handling method-specific field visibility
// and building the allocation/distribution JSON from form inputs.
export default class extends Controller {
    static targets = [
        "sharesOptions",
        "perTicketOptions",
        "minimumOption",
        "flatFeeOptions",
        "allocationSection",
        "performerPercentage",
        "housePercentage",
        "allocationJson",
        "overridesSection",
        "overridesList",
        "overrideRow",
        "overridePerTicket",
        "overrideMinimum",
        "overrideShares",
        "overrideFlatAmount",
        "personSelect",
        "newOverridePerTicket",
        "newOverrideMinimum",
        "newOverrideShares",
        "newOverrideFlatAmount",
        "newPerTicketRate",
        "newMinimum",
        "newShares",
        "newFlatAmount",
        // Individual allocations targets
        "individualAllocationsSection",
        "individualAllocationsList",
        "individualAllocationRow",
        "individualAllocationPersonSelect",
        "newAllocationPercentage",
        "newAllocationLabel"
    ]

    connect() {
        this.updateVisibility()
        this.updatePercentages()
        this.individualAllocationIndex = this.individualAllocationRowTargets.length
    }

    // Called when distribution method changes
    updateMethod() {
        this.updateVisibility()
    }

    // Get the currently selected distribution method
    get selectedMethod() {
        const checked = this.element.querySelector('input[name="rules[distribution][method]"]:checked')
        return checked ? checked.value : "equal"
    }

    // Show/hide method-specific options
    updateVisibility() {
        const method = this.selectedMethod

        // Hide all options first
        if (this.hasSharesOptionsTarget) {
            this.sharesOptionsTarget.classList.add("hidden")
        }
        if (this.hasPerTicketOptionsTarget) {
            this.perTicketOptionsTarget.classList.add("hidden")
        }
        if (this.hasMinimumOptionTarget) {
            this.minimumOptionTarget.classList.add("hidden")
        }
        if (this.hasFlatFeeOptionsTarget) {
            this.flatFeeOptionsTarget.classList.add("hidden")
        }
        if (this.hasAllocationSectionTarget) {
            // Show allocation section for all methods except flat_fee
            if (method === "flat_fee") {
                this.allocationSectionTarget.classList.add("hidden")
            } else {
                this.allocationSectionTarget.classList.remove("hidden")
            }
        }

        // Show/hide individual allocations section for all methods except flat_fee
        if (this.hasIndividualAllocationsSectionTarget) {
            if (method === "flat_fee") {
                this.individualAllocationsSectionTarget.classList.add("hidden")
            } else {
                this.individualAllocationsSectionTarget.classList.remove("hidden")
            }
        }

        // Show the relevant options
        switch (method) {
            case "shares":
                if (this.hasSharesOptionsTarget) {
                    this.sharesOptionsTarget.classList.remove("hidden")
                }
                break
            case "per_ticket":
                if (this.hasPerTicketOptionsTarget) {
                    this.perTicketOptionsTarget.classList.remove("hidden")
                }
                break
            case "per_ticket_guaranteed":
                if (this.hasPerTicketOptionsTarget) {
                    this.perTicketOptionsTarget.classList.remove("hidden")
                }
                if (this.hasMinimumOptionTarget) {
                    this.minimumOptionTarget.classList.remove("hidden")
                }
                break
            case "flat_fee":
                if (this.hasFlatFeeOptionsTarget) {
                    this.flatFeeOptionsTarget.classList.remove("hidden")
                }
                break
        }

        // Update overrides section visibility
        this.updateOverridesVisibility(method)
    }

    // Show/hide the overrides section and appropriate fields
    updateOverridesVisibility(method) {
        // Hide overrides section for equal split (not useful)
        if (this.hasOverridesSectionTarget) {
            if (method === "equal") {
                this.overridesSectionTarget.classList.add("hidden")
            } else {
                this.overridesSectionTarget.classList.remove("hidden")
            }
        }

        // Update visibility for existing override rows
        this.overridePerTicketTargets.forEach(el => {
            el.classList.toggle("hidden", !["per_ticket", "per_ticket_guaranteed"].includes(method))
            if (["per_ticket", "per_ticket_guaranteed"].includes(method)) {
                el.classList.add("flex", "items-center", "gap-2")
            }
        })

        this.overrideMinimumTargets.forEach(el => {
            el.classList.toggle("hidden", method !== "per_ticket_guaranteed")
            if (method === "per_ticket_guaranteed") {
                el.classList.add("flex", "items-center", "gap-2")
            }
        })

        this.overrideSharesTargets.forEach(el => {
            el.classList.toggle("hidden", method !== "shares")
            if (method === "shares") {
                el.classList.add("flex", "items-center", "gap-2")
            }
        })

        this.overrideFlatAmountTargets.forEach(el => {
            el.classList.toggle("hidden", method !== "flat_fee")
            if (method === "flat_fee") {
                el.classList.add("flex", "items-center", "gap-2")
            }
        })

        // Update visibility for new override inputs
        if (this.hasNewOverridePerTicketTarget) {
            this.newOverridePerTicketTarget.classList.toggle("hidden", !["per_ticket", "per_ticket_guaranteed"].includes(method))
            if (["per_ticket", "per_ticket_guaranteed"].includes(method)) {
                this.newOverridePerTicketTarget.classList.add("flex", "items-center", "gap-2")
            }
        }

        if (this.hasNewOverrideMinimumTarget) {
            this.newOverrideMinimumTarget.classList.toggle("hidden", method !== "per_ticket_guaranteed")
            if (method === "per_ticket_guaranteed") {
                this.newOverrideMinimumTarget.classList.add("flex", "items-center", "gap-2")
            }
        }

        if (this.hasNewOverrideSharesTarget) {
            this.newOverrideSharesTarget.classList.toggle("hidden", method !== "shares")
            if (method === "shares") {
                this.newOverrideSharesTarget.classList.add("flex", "items-center", "gap-2")
            }
        }

        if (this.hasNewOverrideFlatAmountTarget) {
            this.newOverrideFlatAmountTarget.classList.toggle("hidden", method !== "flat_fee")
            if (method === "flat_fee") {
                this.newOverrideFlatAmountTarget.classList.add("flex", "items-center", "gap-2")
            }
        }
    }

    // Add a new performer override
    addOverride() {
        if (!this.hasPersonSelectTarget) return

        const select = this.personSelectTarget
        const personId = select.value
        const personName = select.options[select.selectedIndex]?.dataset?.name

        if (!personId) {
            alert("Please select a person")
            return
        }

        const method = this.selectedMethod

        // Build the new override row HTML
        const row = document.createElement("div")
        row.className = "flex items-center gap-3 p-3 bg-gray-50 rounded-lg"
        row.dataset.payoutSchemeFormTarget = "overrideRow"

        let fieldsHtml = `
            <div class="flex-1">
                <div class="font-medium text-gray-900">${this.escapeHtml(personName)}</div>
                <input type="hidden" name="rules[performer_overrides][${personId}][person_id]" value="${personId}">
            </div>
        `

        // Per-ticket rate field
        const perTicketRate = this.hasNewPerTicketRateTarget ? this.newPerTicketRateTarget.value : ""
        const showPerTicket = ["per_ticket", "per_ticket_guaranteed"].includes(method)
        fieldsHtml += `
            <div data-payout-scheme-form-target="overridePerTicket" class="${showPerTicket ? 'flex items-center gap-2' : 'hidden'}">
                <span class="text-sm text-gray-500">$</span>
                <input type="number" name="rules[performer_overrides][${personId}][per_ticket_rate]" value="${perTicketRate}" min="0" step="0.01" class="w-20 rounded border border-gray-300 px-2 py-1 text-sm" placeholder="rate">
                <span class="text-sm text-gray-500">/ticket</span>
            </div>
        `

        // Minimum field
        const minimum = this.hasNewMinimumTarget ? this.newMinimumTarget.value : ""
        const showMinimum = method === "per_ticket_guaranteed"
        fieldsHtml += `
            <div data-payout-scheme-form-target="overrideMinimum" class="${showMinimum ? 'flex items-center gap-2' : 'hidden'}">
                <span class="text-sm text-gray-500">min $</span>
                <input type="number" name="rules[performer_overrides][${personId}][minimum]" value="${minimum}" min="0" step="1" class="w-20 rounded border border-gray-300 px-2 py-1 text-sm" placeholder="min">
            </div>
        `

        // Shares field
        const shares = this.hasNewSharesTarget ? this.newSharesTarget.value : ""
        const showShares = method === "shares"
        fieldsHtml += `
            <div data-payout-scheme-form-target="overrideShares" class="${showShares ? 'flex items-center gap-2' : 'hidden'}">
                <input type="number" name="rules[performer_overrides][${personId}][shares]" value="${shares}" min="0" step="0.5" class="w-20 rounded border border-gray-300 px-2 py-1 text-sm" placeholder="shares">
                <span class="text-sm text-gray-500">shares</span>
            </div>
        `

        // Flat amount field
        const flatAmount = this.hasNewFlatAmountTarget ? this.newFlatAmountTarget.value : ""
        const showFlatAmount = method === "flat_fee"
        fieldsHtml += `
            <div data-payout-scheme-form-target="overrideFlatAmount" class="${showFlatAmount ? 'flex items-center gap-2' : 'hidden'}">
                <span class="text-sm text-gray-500">$</span>
                <input type="number" name="rules[performer_overrides][${personId}][flat_amount]" value="${flatAmount}" min="0" step="1" class="w-20 rounded border border-gray-300 px-2 py-1 text-sm" placeholder="amount">
            </div>
        `

        // Remove button
        fieldsHtml += `
            <button type="button" data-action="click->payout-scheme-form#removeOverride" class="text-gray-400 hover:text-red-500">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                </svg>
            </button>
        `

        row.innerHTML = fieldsHtml

        // Add to the list
        if (this.hasOverridesListTarget) {
            this.overridesListTarget.appendChild(row)
        }

        // Remove the person from the select
        select.querySelector(`option[value="${personId}"]`)?.remove()

        // Clear the input fields
        if (this.hasNewPerTicketRateTarget) this.newPerTicketRateTarget.value = ""
        if (this.hasNewMinimumTarget) this.newMinimumTarget.value = ""
        if (this.hasNewSharesTarget) this.newSharesTarget.value = ""
        if (this.hasNewFlatAmountTarget) this.newFlatAmountTarget.value = ""

        // Reset select
        select.value = ""
    }

    // Remove a performer override
    removeOverride(event) {
        const row = event.target.closest('[data-payout-scheme-form-target="overrideRow"]')
        if (!row) return

        // Get the person info to add back to select
        const hiddenInput = row.querySelector('input[type="hidden"]')
        const nameEl = row.querySelector('.font-medium')

        if (hiddenInput && nameEl && this.hasPersonSelectTarget) {
            const personId = hiddenInput.value
            const personName = nameEl.textContent

            // Add back to select
            const option = document.createElement("option")
            option.value = personId
            option.textContent = personName
            option.dataset.name = personName
            this.personSelectTarget.appendChild(option)
        }

        // Remove the row
        row.remove()
    }

    // Update the performer percentage display when house percentage changes
    updatePercentages() {
        if (!this.hasHousePercentageTarget || !this.hasPerformerPercentageTarget) {
            return
        }

        const housePercent = parseFloat(this.housePercentageTarget.value) || 0
        const performerPercent = Math.max(0, 100 - housePercent)
        this.performerPercentageTarget.textContent = `${performerPercent}%`

        // Update the hidden allocation JSON
        this.updateAllocationJson()
    }

    // Update the allocation JSON hidden field
    updateAllocationJson() {
        if (!this.hasAllocationJsonTarget) {
            return
        }

        const housePercent = parseFloat(this.housePercentageTarget?.value) || 0
        this.allocationJsonTarget.value = JSON.stringify({
            type: "percentage",
            value: housePercent,
            to: "house"
        })
    }

    // Add a new individual allocation (percentage to a specific person)
    addIndividualAllocation() {
        if (!this.hasIndividualAllocationPersonSelectTarget) return

        const select = this.individualAllocationPersonSelectTarget
        const personId = select.value
        const personName = select.options[select.selectedIndex]?.dataset?.name

        if (!personId) {
            alert("Please select a person")
            return
        }

        const percentage = this.hasNewAllocationPercentageTarget ? this.newAllocationPercentageTarget.value : "10"
        const label = this.hasNewAllocationLabelTarget ? this.newAllocationLabelTarget.value : ""

        // Build the new row HTML
        const row = document.createElement("div")
        row.className = "flex items-center gap-3 p-3 bg-gray-50 rounded-lg"
        row.dataset.payoutSchemeFormTarget = "individualAllocationRow"

        const index = this.individualAllocationIndex++

        row.innerHTML = `
            <div class="flex-1">
                <div class="font-medium text-gray-900">${this.escapeHtml(personName)}</div>
                <input type="hidden" name="rules[individual_allocations][${index}][person_id]" value="${personId}">
            </div>
            <div class="flex items-center gap-2">
                <input type="number" name="rules[individual_allocations][${index}][percentage]" value="${this.escapeHtml(percentage)}" min="0" max="100" step="0.5" class="w-20 rounded border border-gray-300 px-2 py-1 text-sm">
                <span class="text-sm text-gray-500">%</span>
            </div>
            <div class="flex-1">
                <input type="text" name="rules[individual_allocations][${index}][label]" value="${this.escapeHtml(label)}" placeholder="Label (optional)" class="w-full rounded border border-gray-300 px-2 py-1 text-sm">
            </div>
            <button type="button" data-action="click->payout-scheme-form#removeIndividualAllocation" class="text-gray-400 hover:text-red-500">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                </svg>
            </button>
        `

        // Add to the list
        if (this.hasIndividualAllocationsListTarget) {
            this.individualAllocationsListTarget.appendChild(row)
        }

        // Remove the person from the select
        select.querySelector(`option[value="${personId}"]`)?.remove()

        // Clear the input fields
        if (this.hasNewAllocationPercentageTarget) this.newAllocationPercentageTarget.value = "10"
        if (this.hasNewAllocationLabelTarget) this.newAllocationLabelTarget.value = ""

        // Reset select
        select.value = ""
    }

    // Remove an individual allocation
    removeIndividualAllocation(event) {
        const row = event.target.closest('[data-payout-scheme-form-target="individualAllocationRow"]')
        if (!row) return

        // Get the person info to add back to select
        const hiddenInput = row.querySelector('input[type="hidden"]')
        const nameEl = row.querySelector('.font-medium')

        if (hiddenInput && nameEl && this.hasIndividualAllocationPersonSelectTarget) {
            const personId = hiddenInput.value
            const personName = nameEl.textContent

            // Add back to select
            const option = document.createElement("option")
            option.value = personId
            option.textContent = personName
            option.dataset.name = personName
            this.individualAllocationPersonSelectTarget.appendChild(option)
        }

        // Remove the row
        row.remove()
    }

    // Escape HTML to prevent XSS
    escapeHtml(text) {
        const div = document.createElement("div")
        div.textContent = text
        return div.innerHTML
    }
}
