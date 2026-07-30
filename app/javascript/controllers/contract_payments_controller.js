import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "description", "amount", "direction", "dueDate", "list", "paymentsJson", "structureJson", "configJson",
        "summary", "summaryDetails", "totalIncoming", "totalOutgoing", "netAmount",
        // Flat fee targets
        "flatFeeConfig", "flatFeeAmount", "flatFeeAmountLabel", "flatFeeDirection", "flatFeeDeposit",
        "flatFeeDepositConfig", "flatFeeDepositAmount", "flatFeeDepositPercent", "flatFeeDepositDue", "flatFeeFinalDue",
        "flatFeeTicketRevenueHint",
        // Per event targets
        "perEventConfig", "perEventAmount", "perEventCount", "perEventDirection", "perEventTiming",
        "perEventUpfrontConfig", "perEventUpfrontDue", "perEventTotal", "perEventCountDisplay", "perEventAmountDisplay",
        "perEventTermsConfig", "perEventDiscount", "perEventDiscountConfig", "perEventDiscountPercent", "perEventTerms",
        "perEventTermsDaysConfig", "perEventTermsDays", "perEventTermsDaysLabel",
        // Structure buttons
        "flatFeeBtn", "perEventBtn", "revenueShareBtn",
        // Revenue share targets
        "revenueShareConfig", "revenueSource", "revenueOurShare", "revenueTheirShare",
        "revenueGuarantee", "revenueGuaranteeConfig", "revenueGuaranteeAmount", "revenueSettlement",
        // Custom targets
        "customConfig",
        // Ticketing (folded into the deal, shown only when we sell)
        "nextButton", "paymentModal", "paymentModalError"
    ]
    static values = {
        existing: Array,
        existingStructure: { type: String, default: "flat_fee" },
        existingConfig: { type: Object, default: {} },
        bookings: { type: Array, default: [] },
        bookingsCount: Number
    }

    connect() {
        this.payments = this.existingValue || []
        this.currentStructure = this.existingStructureValue || "flat_fee"
        // Custom is gone as a choice; treat any leftover as a flat fee.
        if (this.currentStructure === "custom") this.currentStructure = "flat_fee"
        this.eventCount = this.bookingsCountValue || 0
        this.bookingDates = this.bookingsValue || []

        // Payments added by hand live separately from the ones the deal
        // generates, so editing the deal never wipes them out.
        this.extraPayments = (this.existingValue || []).filter((p) => p.extra)

        // Restore saved config first
        this.restoreConfig(this.existingConfigValue || {})

        // Default flat fee final due date to first event if not already set
        if (this.hasFlatFeeFinalDueTarget && !this.flatFeeFinalDueTarget.value && this.bookingDates.length > 0) {
            this.flatFeeFinalDueTarget.value = this.bookingDates[0].split("T")[0]
        }

        // Initialize UI with saved structure
        this.updateStructureButtons()
        this.showConfigPanel(this.currentStructure)

        // Cards first, so the list and totals read the restored answers.
        this.syncChoiceCards()
        // Revenue share needs tickets — gate it before the first render (a brand-new
        // contract starts on "No tickets", so it should start disabled).
        this.syncRevenueShareAvailability()
        this.updateSummary()
        this.updateNextLabel()
    }

    // The radio-card groups mirror their selection into a hidden input, so the
    // rest of this controller keeps reading and writing a plain `.value` and
    // doesn't care that these are cards rather than a <select>.
    onChoiceChange(event) {
        const group = event.target.closest("[data-choice-group]")
        if (!group) return
        const hidden = group.querySelector('input[type="hidden"]')
        if (hidden) hidden.value = event.target.value
        // Every choice card feeds the deal (settlement timing, guarantee on/off,
        // deposit, discount, direction…), so re-render the generated preview. This
        // runs before any card-specific action (it's first in the action list), so
        // the hidden value the preview reads is already current.
        this.updateSummary()
    }

    // The reverse: after restoring saved config (which writes the hidden
    // inputs), check the card that matches.
    syncChoiceCards() {
        this.element.querySelectorAll("[data-choice-group]").forEach((group) => {
            const hidden = group.querySelector('input[type="hidden"]')
            if (!hidden) return
            const radio = group.querySelector(`input[type="radio"][value="${CSS.escape(hidden.value)}"]`)
            if (radio) radio.checked = true
        })

        // Panels revealed by a yes/no group have to match the restored answer.
        if (this.hasFlatFeeDepositConfigTarget) {
            this.flatFeeDepositConfigTarget.classList.toggle("hidden", !this.depositOn)
        }
        if (this.hasPerEventDiscountConfigTarget) {
            this.perEventDiscountConfigTarget.classList.toggle("hidden", !this.volumeDiscountOn)
        }
        if (this.hasRevenueGuaranteeConfigTarget) {
            this.revenueGuaranteeConfigTarget.classList.toggle("hidden", !this.guaranteeOn)
        }
    }

    // --- The add-a-payment modal ------------------------------------------

    openPaymentModal() {
        if (!this.hasPaymentModalTarget) return
        this.hidePaymentModalError()
        this.paymentModalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")
        if (this.hasDescriptionTarget) this.descriptionTarget.focus()
    }

    closePaymentModal() {
        if (!this.hasPaymentModalTarget) return
        this.paymentModalTarget.classList.add("hidden")
        document.body.classList.remove("overflow-hidden")
    }

    showPaymentModalError(message) {
        if (!this.hasPaymentModalErrorTarget) return
        this.paymentModalErrorTarget.textContent = message
        this.paymentModalErrorTarget.classList.remove("hidden")
    }

    hidePaymentModalError() {
        if (!this.hasPaymentModalErrorTarget) return
        this.paymentModalErrorTarget.classList.add("hidden")
    }

    // Ticketing is its own step, and only when WE sell — so what comes next
    // changes with this answer. Keep the button honest about where it goes.
    onWhoSellsChange() {
        this.updateNextLabel()
        this.syncRevenueShareAvailability()
        // Who holds the ticket money flips the revenue-share direction and can
        // change the structure, so re-render the generated preview + totals.
        this.updateSummary()
    }

    updateNextLabel() {
        if (!this.hasNextButtonTarget) return
        const button = this.nextButtonTarget.querySelector("button")
        if (!button) return
        const weSell = this.whoSellsTickets === "org"
        button.textContent = weSell ? "Next: Ticketing" : "Next: Services"
    }

    // "org" (we sell + hold the money), "contractor" (they sell), or "" (no tickets).
    get whoSellsTickets() {
        const checked = this.element.querySelector('input[name="who_sells_tickets"]:checked')
        return checked ? checked.value : ""
    }

    // Revenue share splits ticket revenue, so it only makes sense when tickets are
    // sold. With "No tickets", disable that option and fall back to the default
    // Flat Fee if it was selected. Per Event stays available (a set charge either way).
    syncRevenueShareAvailability() {
        const ticketsSold = this.whoSellsTickets !== ""

        if (this.hasRevenueShareBtnTarget) {
            const btn = this.revenueShareBtnTarget
            btn.disabled = !ticketsSold
            btn.classList.toggle("opacity-40", !ticketsSold)
            btn.classList.toggle("cursor-not-allowed", !ticketsSold)
            btn.classList.toggle("pointer-events-none", !ticketsSold)
            btn.title = ticketsSold ? "" : "Revenue share needs tickets — choose who sells them above."
        }

        if (!ticketsSold && this.currentStructure === "revenue_share") {
            this.currentStructure = "flat_fee"
            this.updateStructureJson()
            this.updateStructureButtons()
            this.showConfigPanel("flat_fee")
        }
    }

    // Who holds the ticket money decides how a revenue share settles: if we sell,
    // we hold all of it and pay them THEIR share (outgoing); if they sell, they pay
    // us OUR share (incoming).
    revenueShareSettlement(ourShare) {
        if (this.whoSellsTickets === "org") {
            return { share: Math.max(0, 100 - ourShare), direction: "outgoing", recipient: "them" }
        }
        return { share: ourShare, direction: "incoming", recipient: "us" }
    }

    restoreConfig(config) {
        if (!config || Object.keys(config).length === 0) return

        // Restore flat fee config
        if (this.hasFlatFeeAmountTarget && config.flat_fee_amount) {
            this.flatFeeAmountTarget.value = config.flat_fee_amount
        }
        if (this.hasFlatFeeDirectionTarget && config.flat_fee_direction) {
            this.flatFeeDirectionTarget.value = config.flat_fee_direction
            // Restore ticket revenue hint and label
            const isTicketRevenue = config.flat_fee_direction === "ticket_revenue_minus_fee"
            if (this.hasFlatFeeTicketRevenueHintTarget) {
                this.flatFeeTicketRevenueHintTarget.classList.toggle("hidden", !isTicketRevenue)
            }
            if (this.hasFlatFeeAmountLabelTarget) {
                this.flatFeeAmountLabelTarget.textContent = isTicketRevenue ? "Our Fee (Deduction from Ticket Revenue)" : "Total Contract Amount"
            }
        }
        if (this.hasFlatFeeDepositTarget && config.flat_fee_has_deposit) {
            this.flatFeeDepositTarget.value = config.flat_fee_has_deposit ? "yes" : "no"
            if (this.hasFlatFeeDepositConfigTarget) {
                this.flatFeeDepositConfigTarget.classList.toggle("hidden", !config.flat_fee_has_deposit)
            }
        }
        if (this.hasFlatFeeDepositAmountTarget && config.flat_fee_deposit_amount) {
            this.flatFeeDepositAmountTarget.value = config.flat_fee_deposit_amount
        }
        if (this.hasFlatFeeDepositPercentTarget && config.flat_fee_deposit_percent) {
            this.flatFeeDepositPercentTarget.value = config.flat_fee_deposit_percent
        }
        if (this.hasFlatFeeDepositDueTarget && config.flat_fee_deposit_due) {
            this.flatFeeDepositDueTarget.value = config.flat_fee_deposit_due
        }
        if (this.hasFlatFeeFinalDueTarget && config.flat_fee_final_due) {
            this.flatFeeFinalDueTarget.value = config.flat_fee_final_due
        }

        // Restore per event config
        if (this.hasPerEventAmountTarget && config.per_event_amount) {
            this.perEventAmountTarget.value = config.per_event_amount
        }
        if (this.hasPerEventDirectionTarget && config.per_event_direction) {
            this.perEventDirectionTarget.value = config.per_event_direction
        }
        if (this.hasPerEventTimingTarget && config.per_event_timing) {
            this.perEventTimingTarget.value = config.per_event_timing
            // Show/hide timing-related panels
            const isUpfront = config.per_event_timing === "upfront"
            if (this.hasPerEventUpfrontConfigTarget) {
                this.perEventUpfrontConfigTarget.classList.toggle("hidden", !isUpfront)
            }
            if (this.hasPerEventTermsConfigTarget) {
                this.perEventTermsConfigTarget.classList.toggle("hidden", isUpfront)
            }
            if (this.hasPerEventTermsDaysConfigTarget) {
                // Show days config only if per_event and terms is before/after
                const showDays = !isUpfront && (config.per_event_terms === "before" || config.per_event_terms === "after")
                this.perEventTermsDaysConfigTarget.classList.toggle("hidden", !showDays)
            }
        }
        if (this.hasPerEventTermsTarget && config.per_event_terms) {
            this.perEventTermsTarget.value = config.per_event_terms
        }
        if (this.hasPerEventTermsDaysTarget && config.per_event_terms_days) {
            this.perEventTermsDaysTarget.value = config.per_event_terms_days
        }
        if (this.hasPerEventTermsDaysLabelTarget && config.per_event_terms) {
            if (config.per_event_terms === "before") {
                this.perEventTermsDaysLabelTarget.textContent = "Days before event"
            } else if (config.per_event_terms === "after") {
                this.perEventTermsDaysLabelTarget.textContent = "Days after event"
            }
        }
        if (this.hasPerEventUpfrontDueTarget && config.per_event_upfront_due) {
            this.perEventUpfrontDueTarget.value = config.per_event_upfront_due
        }
        if (this.hasPerEventDiscountTarget && config.per_event_has_discount) {
            this.perEventDiscountTarget.value = config.per_event_has_discount ? "yes" : "no"
            if (this.hasPerEventDiscountConfigTarget) {
                this.perEventDiscountConfigTarget.classList.toggle("hidden", !config.per_event_has_discount)
            }
        }
        if (this.hasPerEventDiscountPercentTarget && config.per_event_discount_percent) {
            this.perEventDiscountPercentTarget.value = config.per_event_discount_percent
        }

        // Restore revenue share config
        if (this.hasRevenueSourceTarget && config.revenue_source) {
            this.revenueSourceTarget.value = config.revenue_source
        }
        if (this.hasRevenueOurShareTarget && config.revenue_our_share) {
            this.revenueOurShareTarget.value = config.revenue_our_share
        }
        if (this.hasRevenueTheirShareTarget && config.revenue_their_share) {
            this.revenueTheirShareTarget.value = config.revenue_their_share
        }
        if (this.hasRevenueGuaranteeTarget && config.revenue_has_guarantee) {
            this.revenueGuaranteeTarget.value = config.revenue_has_guarantee ? "yes" : "no"
            if (this.hasRevenueGuaranteeConfigTarget) {
                this.revenueGuaranteeConfigTarget.classList.toggle("hidden", !config.revenue_has_guarantee)
            }
        }
        if (this.hasRevenueGuaranteeAmountTarget && config.revenue_guarantee_amount) {
            this.revenueGuaranteeAmountTarget.value = config.revenue_guarantee_amount
        }
        if (this.hasRevenueSettlementTarget && config.revenue_settlement) {
            this.revenueSettlementTarget.value = config.revenue_settlement
        }

        // Update per-event total display
        this.updatePerEventTotal()
    }

    collectConfig() {
        return {
            // Flat fee config
            flat_fee_amount: this.hasFlatFeeAmountTarget ? this.flatFeeAmountTarget.value : "",
            flat_fee_direction: this.hasFlatFeeDirectionTarget ? this.flatFeeDirectionTarget.value : "incoming",
            flat_fee_has_deposit: this.depositOn,
            flat_fee_deposit_amount: this.hasFlatFeeDepositAmountTarget ? this.flatFeeDepositAmountTarget.value : "",
            flat_fee_deposit_percent: this.hasFlatFeeDepositPercentTarget ? this.flatFeeDepositPercentTarget.value : "",
            flat_fee_deposit_due: this.hasFlatFeeDepositDueTarget ? this.flatFeeDepositDueTarget.value : "",
            flat_fee_final_due: this.hasFlatFeeFinalDueTarget ? this.flatFeeFinalDueTarget.value : "",

            // Per event config
            per_event_amount: this.hasPerEventAmountTarget ? this.perEventAmountTarget.value : "",
            per_event_direction: this.hasPerEventDirectionTarget ? this.perEventDirectionTarget.value : "incoming",
            per_event_timing: this.hasPerEventTimingTarget ? this.perEventTimingTarget.value : "per_event",
            per_event_terms: this.hasPerEventTermsTarget ? this.perEventTermsTarget.value : "same_day",
            per_event_terms_days: this.hasPerEventTermsDaysTarget ? this.perEventTermsDaysTarget.value : "7",
            per_event_upfront_due: this.hasPerEventUpfrontDueTarget ? this.perEventUpfrontDueTarget.value : "",
            per_event_has_discount: this.volumeDiscountOn,
            per_event_discount_percent: this.hasPerEventDiscountPercentTarget ? this.perEventDiscountPercentTarget.value : "",

            // Revenue share config
            revenue_source: this.hasRevenueSourceTarget ? this.revenueSourceTarget.value : "ticket_sales",
            revenue_our_share: this.hasRevenueOurShareTarget ? this.revenueOurShareTarget.value : "50",
            revenue_their_share: this.hasRevenueTheirShareTarget ? this.revenueTheirShareTarget.value : "50",
            revenue_has_guarantee: this.guaranteeOn,
            revenue_guarantee_amount: this.hasRevenueGuaranteeAmountTarget ? this.revenueGuaranteeAmountTarget.value : "",
            revenue_settlement: this.hasRevenueSettlementTarget ? this.revenueSettlementTarget.value : "after_event"
        }
    }

    selectStructureBtn(event) {
        const structure = event.currentTarget.dataset.structure
        this.currentStructure = structure
        this.updateStructureJson()
        this.updateStructureButtons()
        this.showConfigPanel(structure)
        this.updateSummary()
    }

    updateStructureButtons() {
        const activeClasses = "bg-pink-500 text-white border-pink-500"
        const inactiveClasses = "bg-white text-gray-700 border-gray-300 hover:border-pink-400"

        const buttons = [
            { target: "flatFeeBtn", structure: "flat_fee" },
            { target: "perEventBtn", structure: "per_event" },
            { target: "revenueShareBtn", structure: "revenue_share" }
        ]

        buttons.forEach(({ target, structure }) => {
            const btn = this[`has${target.charAt(0).toUpperCase() + target.slice(1)}Target`] ? this[`${target}Target`] : null
            if (btn) {
                btn.className = btn.className.replace(/bg-pink-500|bg-white|text-white|text-gray-700|border-pink-500|border-gray-300|hover:border-pink-400/g, '').trim()
                if (this.currentStructure === structure) {
                    btn.classList.add(...activeClasses.split(' '))
                } else {
                    btn.classList.add(...inactiveClasses.split(' '))
                }
            }
        })
    }

    showConfigPanel(structure) {
        // Hide all config panels
        if (this.hasFlatFeeConfigTarget) this.flatFeeConfigTarget.classList.add("hidden")
        if (this.hasPerEventConfigTarget) this.perEventConfigTarget.classList.add("hidden")
        if (this.hasRevenueShareConfigTarget) this.revenueShareConfigTarget.classList.add("hidden")
        if (this.hasCustomConfigTarget) this.customConfigTarget.classList.add("hidden")

        // Show selected config panel
        switch (structure) {
            case "flat_fee":
                if (this.hasFlatFeeConfigTarget) this.flatFeeConfigTarget.classList.remove("hidden")
                break
            case "per_event":
                if (this.hasPerEventConfigTarget) this.perEventConfigTarget.classList.remove("hidden")
                break
            case "revenue_share":
                if (this.hasRevenueShareConfigTarget) this.revenueShareConfigTarget.classList.remove("hidden")
                break
            case "custom":
                if (this.hasCustomConfigTarget) this.customConfigTarget.classList.remove("hidden")
                break
        }
    }

    selectStructure(event) {
        this.currentStructure = event.target.value
        this.updateStructureJson()

        // Hide all config panels
        if (this.hasFlatFeeConfigTarget) this.flatFeeConfigTarget.classList.add("hidden")
        if (this.hasPerEventConfigTarget) this.perEventConfigTarget.classList.add("hidden")
        if (this.hasRevenueShareConfigTarget) this.revenueShareConfigTarget.classList.add("hidden")
        if (this.hasCustomConfigTarget) this.customConfigTarget.classList.add("hidden")

        // Show selected config panel
        switch (this.currentStructure) {
            case "flat_fee":
                if (this.hasFlatFeeConfigTarget) this.flatFeeConfigTarget.classList.remove("hidden")
                break
            case "per_event":
                if (this.hasPerEventConfigTarget) this.perEventConfigTarget.classList.remove("hidden")
                break
            case "revenue_share":
                if (this.hasRevenueShareConfigTarget) this.revenueShareConfigTarget.classList.remove("hidden")
                break
            case "custom":
                if (this.hasCustomConfigTarget) this.customConfigTarget.classList.remove("hidden")
                break
        }

        // Update summary when structure changes
        this.updateSummaryFromConfig()
    }

    toggleDeposit(event) {
        if (this.hasFlatFeeDepositConfigTarget) {
            this.flatFeeDepositConfigTarget.classList.toggle("hidden", event.target.value !== "yes")
        }
        this.updateSummaryFromConfig()
    }

    get depositOn() {
        return this.hasFlatFeeDepositTarget && this.flatFeeDepositTarget.value === "yes"
    }

    onFlatFeeDirectionChange() {
        const direction = this.hasFlatFeeDirectionTarget ? this.flatFeeDirectionTarget.value : "incoming"
        const isTicketRevenue = direction === "ticket_revenue_minus_fee"

        // Toggle hint
        if (this.hasFlatFeeTicketRevenueHintTarget) {
            this.flatFeeTicketRevenueHintTarget.classList.toggle("hidden", !isTicketRevenue)
        }

        // Update amount label
        if (this.hasFlatFeeAmountLabelTarget) {
            this.flatFeeAmountLabelTarget.textContent = isTicketRevenue ? "Our Fee (Deduction from Ticket Revenue)" : "Total Contract Amount"
        }

        this.updateSummaryFromConfig()
    }

    toggleVolumeDiscount(event) {
        if (this.hasPerEventDiscountConfigTarget) {
            this.perEventDiscountConfigTarget.classList.toggle("hidden", event.target.value !== "yes")
        }
        this.updateSummaryFromConfig()
    }

    toggleGuarantee(event) {
        if (this.hasRevenueGuaranteeConfigTarget) {
            this.revenueGuaranteeConfigTarget.classList.toggle("hidden", event.target.value !== "yes")
        }
    }

    // Both are yes/no card groups mirroring into a hidden input.
    get volumeDiscountOn() {
        return this.hasPerEventDiscountTarget && this.perEventDiscountTarget.value === "yes"
    }

    get guaranteeOn() {
        return this.hasRevenueGuaranteeTarget && this.revenueGuaranteeTarget.value === "yes"
    }

    toggleUpfrontPayment(event) {
        const isUpfront = event.target.value === "upfront"

        if (this.hasPerEventUpfrontConfigTarget) {
            this.perEventUpfrontConfigTarget.classList.toggle("hidden", !isUpfront)
        }
        if (this.hasPerEventTermsConfigTarget) {
            this.perEventTermsConfigTarget.classList.toggle("hidden", isUpfront)
        }
        if (this.hasPerEventTermsDaysConfigTarget) {
            // The "days before/after event" field belongs to the terms dropdown, not
            // the timing toggle — only show it for event-by-event AND before/after
            // terms. (Toggling to upfront and back must not resurrect it on same_day.)
            const terms = this.hasPerEventTermsTarget ? this.perEventTermsTarget.value : ""
            const showDays = !isUpfront && (terms === "before" || terms === "after")
            this.perEventTermsDaysConfigTarget.classList.toggle("hidden", !showDays)

            if (showDays && this.hasPerEventTermsDaysLabelTarget) {
                this.perEventTermsDaysLabelTarget.textContent = terms === "before" ? "Days before event" : "Days after event"
            }
        }

        // Update the per-event total display
        this.updatePerEventTotal()
    }

    togglePaymentTermsDays(event) {
        const terms = event.target.value
        const showDays = terms === "before" || terms === "after"

        if (this.hasPerEventTermsDaysConfigTarget) {
            this.perEventTermsDaysConfigTarget.classList.toggle("hidden", !showDays)
        }

        // Update label based on before/after
        if (this.hasPerEventTermsDaysLabelTarget && showDays) {
            this.perEventTermsDaysLabelTarget.textContent = terms === "before" ? "Days before event" : "Days after event"
        }
    }

    updatePerEventTotal() {
        const amount = parseFloat(this.hasPerEventAmountTarget ? this.perEventAmountTarget.value : 0) || 0
        const count = this.eventCount || 1
        const total = amount * count

        if (this.hasPerEventTotalTarget) {
            this.perEventTotalTarget.textContent = `$${total.toFixed(2)}`
        }
        if (this.hasPerEventCountDisplayTarget) {
            this.perEventCountDisplayTarget.textContent = count
        }
        if (this.hasPerEventAmountDisplayTarget) {
            this.perEventAmountDisplayTarget.textContent = amount.toFixed(2)
        }
    }

    syncRevenueShare(event) {
        const target = event.target
        const value = parseInt(target.value) || 0

        if (target === this.revenueOurShareTarget && this.hasRevenueTheirShareTarget) {
            this.revenueTheirShareTarget.value = Math.max(0, 100 - value)
        } else if (target === this.revenueTheirShareTarget && this.hasRevenueOurShareTarget) {
            this.revenueOurShareTarget.value = Math.max(0, 100 - value)
        }

        this.updateSummaryFromConfig()
    }

    // Live update summary based on current structure configuration
    updateSummaryFromConfig() {
        let incoming = 0
        let outgoing = 0
        let details = []

        switch (this.currentStructure) {
            case "flat_fee":
                const flatAmount = parseFloat(this.hasFlatFeeAmountTarget ? this.flatFeeAmountTarget.value : 0) || 0
                const flatDirection = this.hasFlatFeeDirectionTarget ? this.flatFeeDirectionTarget.value : "incoming"

                if (flatDirection === "ticket_revenue_minus_fee") {
                    // Ticket revenue minus our fee: we keep $X, they get the rest
                    if (flatAmount > 0) {
                        incoming = flatAmount
                        details.push({ label: "Our fee (from ticket revenue)", amount: flatAmount })
                        details.push({ label: "They receive", amount: "TBD (ticket revenue − fee)" })
                    }
                    break
                }

                // Check for deposit
                const hasDeposit = this.depositOn
                let depositAmount = 0
                let remainingAmount = flatAmount

                if (hasDeposit && flatAmount > 0) {
                    const depositFixed = parseFloat(this.hasFlatFeeDepositAmountTarget ? this.flatFeeDepositAmountTarget.value : 0) || 0
                    const depositPercent = parseFloat(this.hasFlatFeeDepositPercentTarget ? this.flatFeeDepositPercentTarget.value : 0) || 0

                    if (depositFixed > 0) {
                        depositAmount = depositFixed
                    } else if (depositPercent > 0) {
                        depositAmount = flatAmount * (depositPercent / 100)
                    }

                    remainingAmount = flatAmount - depositAmount

                    if (depositAmount > 0) {
                        details.push({ label: "Deposit", amount: depositAmount })
                        details.push({ label: "Remaining balance", amount: remainingAmount })
                    }
                }

                if (flatDirection === "incoming") {
                    incoming = flatAmount
                } else {
                    outgoing = flatAmount
                }
                break

            case "per_event":
                const perEventAmount = parseFloat(this.hasPerEventAmountTarget ? this.perEventAmountTarget.value : 0) || 0
                const perEventCount = this.eventCount || 1
                const perEventDirection = this.hasPerEventDirectionTarget ? this.perEventDirectionTarget.value : "incoming"
                let perEventTotal = perEventAmount * perEventCount

                // Update the display values
                this.updatePerEventTotal()

                // Check for volume discount
                const hasDiscount = this.volumeDiscountOn
                let discountAmount = 0

                if (hasDiscount && perEventTotal > 0) {
                    const discountPercent = parseFloat(this.hasPerEventDiscountPercentTarget ? this.perEventDiscountPercentTarget.value : 0) || 0
                    if (discountPercent > 0) {
                        discountAmount = perEventTotal * (discountPercent / 100)
                        details.push({ label: `${perEventCount} events × $${perEventAmount.toFixed(2)}`, amount: perEventTotal })
                        details.push({ label: `Volume discount (${discountPercent}%)`, amount: -discountAmount })
                        perEventTotal = perEventTotal - discountAmount
                    }
                }

                if (perEventDirection === "incoming") {
                    incoming = perEventTotal
                } else {
                    outgoing = perEventTotal
                }
                break

            case "revenue_share":
                // Revenue share is estimated based on potential revenue - show as TBD
                break

            case "custom":
                // For custom, use the payments array
                incoming = this.payments
                    .filter(p => p.direction === "incoming")
                    .reduce((sum, p) => sum + p.amount, 0)
                outgoing = this.payments
                    .filter(p => p.direction === "outgoing")
                    .reduce((sum, p) => sum + p.amount, 0)
                break
        }

        const net = incoming - outgoing

        // Render detail lines
        if (this.hasSummaryDetailsTarget) {
            if (details.length > 0) {
                this.summaryDetailsTarget.innerHTML = details.map(d => {
                    if (typeof d.amount === "string") {
                        return `<div class="flex justify-between">
                            <span>${d.label}</span>
                            <span class="text-gray-500 italic">${d.amount}</span>
                        </div>`
                    }
                    return `<div class="flex justify-between">
                        <span>${d.label}</span>
                        <span class="${d.amount < 0 ? 'text-green-600' : ''}">${d.amount < 0 ? '-' : ''}$${Math.abs(d.amount).toFixed(2)}</span>
                    </div>`
                }).join("")
                this.summaryDetailsTarget.classList.remove("hidden")
            } else {
                this.summaryDetailsTarget.innerHTML = ""
                this.summaryDetailsTarget.classList.add("hidden")
            }
        }

        if (this.hasTotalIncomingTarget) this.totalIncomingTarget.textContent = `$${incoming.toFixed(2)}`
        if (this.hasTotalOutgoingTarget) this.totalOutgoingTarget.textContent = `$${outgoing.toFixed(2)}`
        if (this.hasNetAmountTarget) {
            this.netAmountTarget.classList.remove("text-green-600", "text-red-600", "text-pink-600")
            if (net > 0) {
                this.netAmountTarget.textContent = `+$${net.toFixed(2)}`
                this.netAmountTarget.classList.add("text-green-600")
            } else if (net < 0) {
                this.netAmountTarget.textContent = `-$${Math.abs(net).toFixed(2)}`
                this.netAmountTarget.classList.add("text-red-600")
            } else {
                this.netAmountTarget.textContent = "$0.00"
                this.netAmountTarget.classList.add("text-pink-600")
            }
        }

        // The list previews what the deal generates, so it follows every change.
        this.renderList()
    }

    addPayment() {
        if (!this.hasDescriptionTarget || !this.hasAmountTarget) return

        const description = this.descriptionTarget.value.trim()
        const amount = parseFloat(this.amountTarget.value)
        const direction = this.hasDirectionTarget ? this.directionTarget.value : "incoming"
        const dueDate = this.hasDueDateTarget ? this.dueDateTarget.value : ""

        if (!amount || isNaN(amount) || amount <= 0) {
            this.showPaymentModalError("Enter an amount greater than zero.")
            return
        }

        if (!dueDate) {
            this.showPaymentModalError("Pick a date this payment is due.")
            return
        }

        this.extraPayments.push({
            description: description || "Payment",
            amount: amount,
            direction: direction,
            due_date: dueDate,
            extra: true
        })

        this.clearForm()
        this.closePaymentModal()
        this.updateSummary()
        this.updateHiddenField()
    }

    removePayment(event) {
        const index = parseInt(event.currentTarget.dataset.index)
        this.extraPayments.splice(index, 1)
        this.updateSummary()
        this.updateHiddenField()
    }

    getDateDaysFromNow(days) {
        const date = new Date()
        date.setDate(date.getDate() + days)
        return date.toISOString().split("T")[0]
    }

    formatDateForInput(date) {
        // Format Date object as YYYY-MM-DD for input fields
        const year = date.getFullYear()
        const month = String(date.getMonth() + 1).padStart(2, '0')
        const day = String(date.getDate()).padStart(2, '0')
        return `${year}-${month}-${day}`
    }

    clearForm() {
        if (this.hasDescriptionTarget) this.descriptionTarget.value = ""
        if (this.hasAmountTarget) this.amountTarget.value = ""
        if (this.hasDueDateTarget) this.dueDateTarget.value = ""
        if (this.hasDirectionTarget) {
            this.directionTarget.value = "incoming"
            this.syncChoiceCards()
        }
    }

    renderList() {
        if (!this.hasListTarget) return

        const generated = this.buildGeneratedPayments()
        const extras = this.extraPayments

        if (generated.length === 0 && extras.length === 0) {
            this.listTarget.innerHTML = `
        <div class="text-center py-8 bg-gray-50 rounded-xl border-2 border-dashed border-gray-200">
          <p class="text-gray-500 text-sm">No payments yet.</p>
          <p class="text-gray-400 text-xs mt-1">Fill in the deal above, or add a payment by hand.</p>
        </div>
      `
            return
        }

        const rows = generated.map((payment) => this.paymentRow(payment, null))
            .concat(extras.map((payment, index) => this.paymentRow(payment, index)))

        this.listTarget.innerHTML = rows.join("")
    }

    // One row. `removeIndex` is null for payments the deal generates — those
    // change by editing the deal, not by deleting them here.
    paymentRow(payment, removeIndex) {
        const incoming = payment.direction === "incoming"
        // Keep TBD prefixed with a dollar sign so it reads as "an amount we
        // don't know yet", not a status.
        const amountText = payment.amount_tbd
            ? "$TBD"
            : `${incoming ? "+" : "-"}$${Number(payment.amount || 0).toFixed(2)}`
        const directionLabel = incoming ? "They pay us" : "We pay them"

        const removeButton = removeIndex === null ? "" : `
        <button type="button" data-action="click->contract-payments#removePayment" data-index="${removeIndex}" class="p-1 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition-colors" aria-label="Remove payment">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>`

        return `
      <div class="flex items-center justify-between gap-3 p-4 bg-white rounded-xl border border-gray-200 shadow-sm">
        <div class="flex-1 min-w-0">
          <div class="text-[11px] uppercase tracking-wide font-semibold ${incoming ? "text-green-700" : "text-red-700"}">${directionLabel}</div>
          <div class="font-medium text-gray-900 mt-0.5 truncate">${payment.description}</div>
          <div class="text-sm text-gray-500">Due ${this.formatDate(payment.due_date)}</div>
        </div>
        <div class="flex items-center gap-3 flex-shrink-0">
          <span class="font-semibold text-lg ${payment.amount_tbd ? "text-gray-400" : incoming ? "text-green-600" : "text-red-600"}">${amountText}</span>
          ${removeButton}
        </div>
      </div>
    `
    }

    updateSummary() {
        this.updateSummaryFromConfig()
    }

    formatDate(dateStr) {
        const date = new Date(dateStr + "T00:00:00")
        return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })
    }

    // A per-event payment is named for the event it pays for, e.g. "Jul 1 event",
    // so the payment reads as the thing it's for rather than "Event 1".
    eventDateLabel(bookingDate) {
        const date = new Date(bookingDate)
        return date.toLocaleDateString("en-US", { month: "short", day: "numeric" })
    }

    updateHiddenField() {
        if (this.hasPaymentsJsonTarget) {
            this.paymentsJsonTarget.value = JSON.stringify(this.payments)
        }
    }

    updateStructureJson() {
        if (this.hasStructureJsonTarget) {
            this.structureJsonTarget.value = this.currentStructure
        }
    }

    // Called before form submission to generate payment line items from the current config
    // What the deal above produces, recomputed on demand so the list can show a
    // live preview and the submit path can use exactly the same thing.
    buildGeneratedPayments() {
        const payments = []

        switch (this.currentStructure) {
            case "flat_fee":
                const flatAmount = parseFloat(this.hasFlatFeeAmountTarget ? this.flatFeeAmountTarget.value : 0) || 0
                const flatDirection = this.hasFlatFeeDirectionTarget ? this.flatFeeDirectionTarget.value : "incoming"
                const flatFinalDue = this.hasFlatFeeFinalDueTarget ? this.flatFeeFinalDueTarget.value : ""
                const hasDeposit = this.depositOn

                if (flatDirection === "ticket_revenue_minus_fee") {
                    // Ticket revenue minus our fee: generate outgoing payment (TBD amount)
                    payments.push({
                        description: `Ticket revenue minus $${flatAmount.toFixed(2)} fee`,
                        source: "Ticket revenue minus fee",
                        amount: 0,
                        amount_tbd: true,
                        direction: "outgoing",
                        due_date: flatFinalDue || this.getDateDaysFromNow(30),
                        notes: `They receive all ticket revenue minus our $${flatAmount.toFixed(2)} deduction.`
                    })
                    break
                }

                if (flatAmount > 0) {
                    if (hasDeposit) {
                        const depositFixed = parseFloat(this.hasFlatFeeDepositAmountTarget ? this.flatFeeDepositAmountTarget.value : 0) || 0
                        const depositPercent = parseFloat(this.hasFlatFeeDepositPercentTarget ? this.flatFeeDepositPercentTarget.value : 0) || 0
                        const depositDue = this.hasFlatFeeDepositDueTarget ? this.flatFeeDepositDueTarget.value : ""

                        let depositAmount = depositFixed > 0 ? depositFixed : (flatAmount * depositPercent / 100)
                        let remainingAmount = flatAmount - depositAmount

                        if (depositAmount > 0) {
                            payments.push({
                                description: "Deposit",
                                source: "Flat fee",
                                amount: depositAmount,
                                direction: flatDirection,
                                due_date: depositDue || this.getDateDaysFromNow(7)
                            })
                        }
                        if (remainingAmount > 0) {
                            payments.push({
                                description: "Final Payment",
                                source: "Flat fee",
                                amount: remainingAmount,
                                direction: flatDirection,
                                due_date: flatFinalDue || this.getDateDaysFromNow(30)
                            })
                        }
                    } else {
                        payments.push({
                            description: "Contract payment",
                            source: "Flat fee",
                            amount: flatAmount,
                            direction: flatDirection,
                            due_date: flatFinalDue || this.getDateDaysFromNow(30)
                        })
                    }
                }
                break

            case "per_event":
                const perEventAmount2 = parseFloat(this.hasPerEventAmountTarget ? this.perEventAmountTarget.value : 0) || 0
                const perEventCount2 = this.eventCount || 1
                const perEventDirection2 = this.hasPerEventDirectionTarget ? this.perEventDirectionTarget.value : "incoming"
                const perEventTiming = this.hasPerEventTimingTarget ? this.perEventTimingTarget.value : "per_event"
                const perEventTerms = this.hasPerEventTermsTarget ? this.perEventTermsTarget.value : "due"
                const perEventTermsDaysRaw = this.hasPerEventTermsDaysTarget ? this.perEventTermsDaysTarget.value : "7"
                const perEventTermsDays = perEventTermsDaysRaw !== "" ? parseInt(perEventTermsDaysRaw) : 7

                // Apply discount if enabled
                const hasDiscount2 = this.volumeDiscountOn
                let discountMultiplier = 1
                if (hasDiscount2) {
                    const discountPercent2 = parseFloat(this.hasPerEventDiscountPercentTarget ? this.perEventDiscountPercentTarget.value : 0) || 0
                    if (discountPercent2 > 0) {
                        discountMultiplier = 1 - (discountPercent2 / 100)
                    }
                }

                const perEventFinalAmount = perEventAmount2 * discountMultiplier

                if (perEventFinalAmount > 0) {
                    if (perEventTiming === "upfront") {
                        // Pay all upfront as single payment
                        const upfrontDue = this.hasPerEventUpfrontDueTarget ? this.perEventUpfrontDueTarget.value : ""
                        payments.push({
                            description: `${perEventCount2} events @ $${perEventFinalAmount.toFixed(2)} each, paid upfront`,
                            source: "Per event",
                            amount: perEventFinalAmount * perEventCount2,
                            direction: perEventDirection2,
                            due_date: upfrontDue || this.getDateDaysFromNow(7)
                        })
                    } else {
                        // Pay for each event individually - create separate payments
                        this.bookingDates.forEach((bookingDate, index) => {
                            let dueDate
                            const eventDate = new Date(bookingDate)

                            if (perEventTerms === "before") {
                                // Due X days before event
                                dueDate = new Date(eventDate)
                                dueDate.setDate(dueDate.getDate() - perEventTermsDays)
                            } else if (perEventTerms === "after") {
                                // Due X days after event
                                dueDate = new Date(eventDate)
                                dueDate.setDate(dueDate.getDate() + perEventTermsDays)
                            } else {
                                // Due on event date
                                dueDate = eventDate
                            }

                            payments.push({
                                description: `${this.eventDateLabel(bookingDate)} event`,
                                source: "Per event",
                                amount: perEventFinalAmount,
                                direction: perEventDirection2,
                                due_date: this.formatDateForInput(dueDate),
                                event_date: bookingDate
                            })
                        })
                    }
                }
                break

            case "revenue_share":
                const ourShare = parseInt(this.hasRevenueOurShareTarget ? this.revenueOurShareTarget.value : 0) || 0
                const hasGuarantee = this.guaranteeOn
                const guaranteeAmount = parseFloat(this.hasRevenueGuaranteeAmountTarget ? this.revenueGuaranteeAmountTarget.value : 0) || 0
                const settlement = this.hasRevenueSettlementTarget ? this.revenueSettlementTarget.value : "same_day"
                // Direction + which share settles depends on who holds the ticket money.
                const settle = this.revenueShareSettlement(ourShare)

                if (ourShare > 0) {
                    // Generate payments based on settlement terms
                    if (settlement === "monthly" && this.bookingDates.length > 0) {
                        // Group bookings by month and create a payment for each month
                        const monthsWithEvents = new Map()
                        this.bookingDates.forEach(bookingDate => {
                            const date = new Date(bookingDate)
                            const monthKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`
                            if (!monthsWithEvents.has(monthKey)) {
                                monthsWithEvents.set(monthKey, date)
                            }
                        })

                        // Create a payment for each month, due at the end of that month
                        Array.from(monthsWithEvents.entries()).forEach(([monthKey, firstEventDate]) => {
                            const [year, month] = monthKey.split('-').map(Number)
                            // Last day of the month (day 0 of next month = last day of current month)
                            const dueDate = new Date(year, month, 0)
                            const monthName = firstEventDate.toLocaleDateString('en-US', { month: 'long', year: 'numeric' })

                            payments.push({
                                description: `${monthName} — ${settle.share}% to ${settle.recipient}`,
                                source: "Revenue share",
                                amount: 0,
                                amount_tbd: true,
                                direction: settle.direction,
                                due_date: this.formatDateForInput(dueDate)
                            })
                        })
                    } else if (settlement === "weekly" && this.bookingDates.length > 0) {
                        // Create weekly settlements based on booking dates
                        const weeksWithEvents = new Map()
                        this.bookingDates.forEach(bookingDate => {
                            const date = new Date(bookingDate)
                            // Get the Monday of that week
                            const day = date.getDay()
                            const diff = date.getDate() - day + (day === 0 ? -6 : 1)
                            const weekStart = new Date(date.setDate(diff))
                            const weekKey = weekStart.toISOString().split('T')[0]
                            if (!weeksWithEvents.has(weekKey)) {
                                weeksWithEvents.set(weekKey, new Date(bookingDate))
                            }
                        })

                        Array.from(weeksWithEvents.entries()).forEach(([weekKey, firstEventDate], index) => {
                            const weekDate = new Date(weekKey)
                            // Due the following Monday
                            const dueDate = new Date(weekDate)
                            dueDate.setDate(dueDate.getDate() + 7)

                            payments.push({
                                description: `Week ${index + 1} — ${settle.share}% to ${settle.recipient}`,
                                source: "Revenue share",
                                amount: 0,
                                amount_tbd: true,
                                direction: settle.direction,
                                due_date: this.formatDateForInput(dueDate)
                            })
                        })
                    } else {
                        // Same day or next day - create one payment per event
                        this.bookingDates.forEach((bookingDate, index) => {
                            const eventDate = new Date(bookingDate)
                            let dueDate = new Date(eventDate)

                            if (settlement === "next_day") {
                                dueDate.setDate(dueDate.getDate() + 1)
                            }

                            payments.push({
                                description: `${this.eventDateLabel(bookingDate)} — ${settle.share}% to ${settle.recipient}`,
                                source: "Revenue share",
                                amount: 0,
                                amount_tbd: true,
                                direction: settle.direction,
                                due_date: this.formatDateForInput(dueDate)
                            })
                        })
                    }
                }
                if (hasGuarantee && guaranteeAmount > 0) {
                    // A minimum guarantee protects the producer's floor, so it flows the
                    // same way as the share settlement (to them when we hold the money).
                    payments.push({
                        description: "Minimum guarantee",
                        source: "Minimum guarantee",
                        amount: guaranteeAmount,
                        direction: settle.direction,
                        due_date: this.getDateDaysFromNow(7)
                    })
                }
                break

            case "custom":
                // Nothing is generated — a custom schedule is entirely by hand.
                break
        }

        return payments
    }

    preparePaymentsForSubmit() {
        // The deal's payments, then anything added by hand.
        this.payments = this.buildGeneratedPayments().concat(this.extraPayments)
        this.updateHiddenField()
        this.updateConfigJson()
    }

    updateConfigJson() {
        if (this.hasConfigJsonTarget) {
            this.configJsonTarget.value = JSON.stringify(this.collectConfig())
        }
    }
}
