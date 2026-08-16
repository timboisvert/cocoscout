import { Controller } from "@hotwired/stimulus"

// Manages the payout scheme form, handling method-specific field visibility
// and building the allocation/distribution JSON from form inputs.
export default class extends Controller {
    static targets = [
        "sharesOptions",
        "perTicketOptions",
        "minimumOption",
        "flatFeeOptions",
        "perActOptions",
        "perActSimple",
        "perActSchedule",
        "perActTiers",
        "actRatesList",
        "actRateRow",
        "actRateLabel",
        "actTiersList",
        "actTierRow",
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
        "overridePerAct",
        "personSelect",
        "newOverridePerTicket",
        "newOverrideMinimum",
        "newOverrideShares",
        "newOverrideFlatAmount",
        "newOverridePerAct",
        "newPerTicketRate",
        "newMinimum",
        "newShares",
        "newFlatAmount",
        "newPerActRate",
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
        this.actTierIndex = this.actTierRowTargets.length
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
        if (this.hasPerActOptionsTarget) {
            this.perActOptionsTarget.classList.add("hidden")
        }

        // Flat fee and per-act pay people directly, so there's no revenue pool
        // to allocate.
        const poolless = ["flat_fee", "per_act"].includes(method)
        if (this.hasAllocationSectionTarget) {
            this.allocationSectionTarget.classList.toggle("hidden", poolless)
        }
        if (this.hasIndividualAllocationsSectionTarget) {
            this.individualAllocationsSectionTarget.classList.toggle("hidden", poolless)
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
            case "per_act":
                if (this.hasPerActOptionsTarget) {
                    this.perActOptionsTarget.classList.remove("hidden")
                }
                this.updateActMode()
                break
        }

        // Update overrides section visibility
        this.updateOverridesVisibility(method)
    }

    // Act pay is either a flat rate per act or a table of act counts.
    get selectedActMode() {
        const checked = this.element.querySelector('input[name="rules[distribution][act_mode]"]:checked')
        return checked ? checked.value : "tiers"
    }

    updateActMode() {
        const mode = this.selectedActMode
        if (this.hasPerActSimpleTarget) this.perActSimpleTarget.classList.toggle("hidden", mode !== "simple")
        if (this.hasPerActScheduleTarget) this.perActScheduleTarget.classList.toggle("hidden", mode !== "schedule")
        if (this.hasPerActTiersTarget) this.perActTiersTarget.classList.toggle("hidden", mode !== "tiers")
    }

    // The schedule rows are positional — the first row is the first act — so
    // adding or removing one renumbers the labels.
    addActRate(event) {
        if (event) event.preventDefault()
        if (!this.hasActRatesListTarget) return

        const row = document.createElement("div")
        row.className = "flex items-center gap-3 p-3 bg-white border border-gray-200 rounded-lg"
        row.dataset.payoutSchemeFormTarget = "actRateRow"
        row.innerHTML = `
            <span class="text-sm text-gray-600 w-24 whitespace-nowrap" data-payout-scheme-form-target="actRateLabel"></span>
            <span class="text-gray-500">$</span>
            <input type="number" name="rules[distribution][act_rates][]" value="0" min="0" step="0.01" class="w-24 rounded-lg border border-gray-300 px-3 py-2.5 shadow-sm focus:border-pink-500 focus:ring-2 focus:ring-pink-500">
            <button type="button" data-action="click->payout-scheme-form#removeActRate" class="ml-auto text-gray-400 hover:text-red-500 cursor-pointer" title="Remove this row">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                </svg>
            </button>
        `

        this.actRatesListTarget.appendChild(row)
        this.renumberActRates()
    }

    removeActRate(event) {
        event.preventDefault()
        event.target.closest('[data-payout-scheme-form-target="actRateRow"]')?.remove()
        this.renumberActRates()
    }

    renumberActRates() {
        this.actRateLabelTargets.forEach((label, index) => {
            label.textContent = `${this.ordinalize(index + 1)} act pays`
        })
    }

    ordinalize(number) {
        const rest = number % 100
        if (rest >= 11 && rest <= 13) return `${number}th`
        switch (number % 10) {
            case 1: return `${number}st`
            case 2: return `${number}nd`
            case 3: return `${number}rd`
            default: return `${number}th`
        }
    }

    // Add another "N acts pays $X" row to the act table.
    addActTier(event) {
        if (event) event.preventDefault()
        if (!this.hasActTiersListTarget) return

        const index = this.actTierIndex++
        const lastRow = this.actTierRowTargets[this.actTierRowTargets.length - 1]
        const nextActs = lastRow ? (parseInt(lastRow.querySelector('input[type="number"]').value, 10) || 0) + 1 : 1

        const row = document.createElement("div")
        row.className = "flex items-center gap-3 p-3 bg-white border border-gray-200 rounded-lg"
        row.dataset.payoutSchemeFormTarget = "actTierRow"
        row.innerHTML = `
            <input type="number" name="rules[distribution][tiers][${index}][acts]" value="${nextActs}" min="1" step="1" class="w-20 rounded-lg border border-gray-300 px-3 py-2.5 shadow-sm focus:border-pink-500 focus:ring-2 focus:ring-pink-500">
            <span class="text-sm text-gray-600 whitespace-nowrap">acts pays</span>
            <span class="text-gray-500">$</span>
            <input type="number" name="rules[distribution][tiers][${index}][amount]" value="0" min="0" step="0.01" class="w-24 rounded-lg border border-gray-300 px-3 py-2.5 shadow-sm focus:border-pink-500 focus:ring-2 focus:ring-pink-500">
            <button type="button" data-action="click->payout-scheme-form#removeActTier" class="ml-auto text-gray-400 hover:text-red-500 cursor-pointer" title="Remove this row">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                </svg>
            </button>
        `

        this.actTiersListTarget.appendChild(row)
    }

    removeActTier(event) {
        event.preventDefault()
        event.target.closest('[data-payout-scheme-form-target="actTierRow"]')?.remove()
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

        this.overridePerActTargets.forEach(el => {
            el.classList.toggle("hidden", method !== "per_act")
            if (method === "per_act") {
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

        if (this.hasNewOverridePerActTarget) {
            this.newOverridePerActTarget.classList.toggle("hidden", method !== "per_act")
            if (method === "per_act") {
                this.newOverridePerActTarget.classList.add("flex", "items-center", "gap-2")
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

        // Per-act rate field
        const perActRate = this.hasNewPerActRateTarget ? this.newPerActRateTarget.value : ""
        const showPerAct = method === "per_act"
        fieldsHtml += `
            <div data-payout-scheme-form-target="overridePerAct" class="${showPerAct ? 'flex items-center gap-2' : 'hidden'}">
                <span class="text-sm text-gray-500">$</span>
                <input type="number" name="rules[performer_overrides][${personId}][per_act_rate]" value="${perActRate}" min="0" step="0.01" class="w-20 rounded border border-gray-300 px-2 py-1 text-sm" placeholder="rate">
                <span class="text-sm text-gray-500">/act</span>
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
        if (this.hasNewPerActRateTarget) this.newPerActRateTarget.value = ""

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
