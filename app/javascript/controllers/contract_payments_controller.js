import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "description", "amount", "direction", "dueDate", "list", "paymentsJson", "structureJson",
        "summary", "summaryDetails", "totalIncoming", "totalOutgoing", "netAmount",
        // Flat fee targets
        "flatFeeConfig", "flatFeeAmount", "flatFeeDirection", "flatFeeDeposit",
        "flatFeeDepositConfig", "flatFeeDepositAmount", "flatFeeDepositPercent", "flatFeeDepositDue", "flatFeeFinalDue",
        // Per event targets
        "perEventConfig", "perEventAmount", "perEventCount", "perEventDirection", "perEventTiming",
        "perEventUpfrontConfig", "perEventUpfrontDue", "perEventTotal", "perEventCountDisplay", "perEventAmountDisplay",
        "perEventTermsConfig", "perEventDiscount", "perEventDiscountConfig", "perEventDiscountPercent", "perEventTerms",
        // Revenue share targets
        "revenueShareConfig", "revenueSource", "revenueOurShare", "revenueTheirShare",
        "revenueGuarantee", "revenueGuaranteeConfig", "revenueGuaranteeAmount", "revenueSettlement",
        // Custom targets
        "customConfig"
    ]
    static values = { existing: Array }

    connect() {
        this.payments = this.existingValue || []
        this.currentStructure = "flat_fee"
        this.renderList()
        this.updateSummary()
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
            this.flatFeeDepositConfigTarget.classList.toggle("hidden", !event.target.checked)
        }
        this.updateSummaryFromConfig()
    }

    toggleVolumeDiscount(event) {
        if (this.hasPerEventDiscountConfigTarget) {
            this.perEventDiscountConfigTarget.classList.toggle("hidden", !event.target.checked)
        }
        this.updateSummaryFromConfig()
    }

    toggleGuarantee(event) {
        if (this.hasRevenueGuaranteeConfigTarget) {
            this.revenueGuaranteeConfigTarget.classList.toggle("hidden", !event.target.checked)
        }
    }

    toggleUpfrontPayment(event) {
        const isUpfront = event.target.value === "upfront"

        if (this.hasPerEventUpfrontConfigTarget) {
            this.perEventUpfrontConfigTarget.classList.toggle("hidden", !isUpfront)
        }
        if (this.hasPerEventTermsConfigTarget) {
            this.perEventTermsConfigTarget.classList.toggle("hidden", isUpfront)
        }

        // Update the per-event total display
        this.updatePerEventTotal()
    }

    updatePerEventTotal() {
        const amount = parseFloat(this.hasPerEventAmountTarget ? this.perEventAmountTarget.value : 0) || 0
        const count = parseInt(this.hasPerEventCountTarget ? this.perEventCountTarget.value : 1) || 1
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
                
                // Check for deposit
                const hasDeposit = this.hasFlatFeeDepositTarget && this.flatFeeDepositTarget.checked
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
                const perEventCount = parseInt(this.hasPerEventCountTarget ? this.perEventCountTarget.value : 1) || 1
                const perEventDirection = this.hasPerEventDirectionTarget ? this.perEventDirectionTarget.value : "incoming"
                let perEventTotal = perEventAmount * perEventCount

                // Update the display values
                this.updatePerEventTotal()
                
                // Check for volume discount
                const hasDiscount = this.hasPerEventDiscountTarget && this.perEventDiscountTarget.checked
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
                this.summaryDetailsTarget.innerHTML = details.map(d => `
                    <div class="flex justify-between">
                        <span>${d.label}</span>
                        <span class="${d.amount < 0 ? 'text-green-600' : ''}">${d.amount < 0 ? '-' : ''}$${Math.abs(d.amount).toFixed(2)}</span>
                    </div>
                `).join("")
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
    }

    addPayment() {
        if (!this.hasDescriptionTarget || !this.hasAmountTarget) return

        const description = this.descriptionTarget.value.trim()
        const amount = parseFloat(this.amountTarget.value)
        const direction = this.hasDirectionTarget ? this.directionTarget.value : "incoming"
        const dueDate = this.hasDueDateTarget ? this.dueDateTarget.value : ""

        if (!amount || isNaN(amount) || amount <= 0) {
            alert("Please enter a valid amount")
            return
        }

        if (!dueDate) {
            alert("Please select a due date")
            return
        }

        this.payments.push({
            description: description || "Payment",
            amount: amount,
            direction: direction,
            due_date: dueDate
        })

        this.clearForm()
        this.renderList()
        this.updateSummary()
        this.updateHiddenField()
    }

    removePayment(event) {
        const index = parseInt(event.currentTarget.dataset.index)
        this.payments.splice(index, 1)
        this.renderList()
        this.updateSummary()
        this.updateHiddenField()
    }

    getDateDaysFromNow(days) {
        const date = new Date()
        date.setDate(date.getDate() + days)
        return date.toISOString().split("T")[0]
    }

    clearForm() {
        if (this.hasDescriptionTarget) this.descriptionTarget.value = ""
        if (this.hasAmountTarget) this.amountTarget.value = ""
        if (this.hasDueDateTarget) this.dueDateTarget.value = ""
    }

    renderList() {
        if (!this.hasListTarget) return

        if (this.payments.length === 0) {
            this.listTarget.innerHTML = `
        <div class="text-center py-8 bg-gray-50 rounded-xl border-2 border-dashed border-gray-200">
          <svg class="w-8 h-8 text-gray-300 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 18.75a60.07 60.07 0 0 1 15.797 2.101c.727.198 1.453-.342 1.453-1.096V18.75M3.75 4.5v.75A.75.75 0 0 1 3 6h-.75m0 0v-.375c0-.621.504-1.125 1.125-1.125H20.25M2.25 6v9m18-10.5v.75c0 .414.336.75.75.75h.75m-1.5-1.5h.375c.621 0 1.125.504 1.125 1.125v9.75c0 .621-.504 1.125-1.125 1.125h-.375m1.5-1.5H21a.75.75 0 0 0-.75.75v.75m0 0H3.75m0 0h-.375a1.125 1.125 0 0 1-1.125-1.125V15m1.5 1.5v-.75A.75.75 0 0 0 3 15h-.75M15 10.5a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm3 0h.008v.008H18V10.5Zm-12 0h.008v.008H6V10.5Z" />
          </svg>
          <p class="text-gray-500 text-sm">No payments scheduled yet.</p>
          <p class="text-gray-400 text-xs mt-1">Add payments above to create a custom schedule.</p>
        </div>
      `
            return
        }

        this.listTarget.innerHTML = this.payments.map((payment, index) => `
      <div class="flex items-center justify-between p-4 bg-white rounded-xl border border-gray-200 shadow-sm">
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <span class="font-medium text-gray-900">${payment.description}</span>
            <span class="text-xs px-2 py-0.5 rounded-full font-medium ${payment.direction === 'incoming' ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}">
              ${payment.direction === 'incoming' ? 'incoming' : 'outgoing'}
            </span>
          </div>
          <div class="text-sm text-gray-500 mt-1">
            Due: ${this.formatDate(payment.due_date)}
          </div>
        </div>
        <div class="flex items-center gap-4">
          <span class="font-semibold text-lg ${payment.direction === 'incoming' ? 'text-green-600' : 'text-red-600'}">
            ${payment.direction === 'incoming' ? '+' : '-'}$${payment.amount.toFixed(2)}
          </span>
          <button type="button" data-action="click->contract-payments#removePayment" data-index="${index}" class="p-1 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition-colors">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>
    `).join("")
    }

    updateSummary() {
        this.updateSummaryFromConfig()
    }

    formatDate(dateStr) {
        const date = new Date(dateStr + "T00:00:00")
        return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })
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
    preparePaymentsForSubmit() {
        const payments = []

        switch (this.currentStructure) {
            case "flat_fee":
                const flatAmount = parseFloat(this.hasFlatFeeAmountTarget ? this.flatFeeAmountTarget.value : 0) || 0
                const flatDirection = this.hasFlatFeeDirectionTarget ? this.flatFeeDirectionTarget.value : "incoming"
                const flatFinalDue = this.hasFlatFeeFinalDueTarget ? this.flatFeeFinalDueTarget.value : ""
                const hasDeposit = this.hasFlatFeeDepositTarget && this.flatFeeDepositTarget.checked

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
                                amount: depositAmount,
                                direction: flatDirection,
                                due_date: depositDue || this.getDateDaysFromNow(7)
                            })
                        }
                        if (remainingAmount > 0) {
                            payments.push({
                                description: "Final Payment",
                                amount: remainingAmount,
                                direction: flatDirection,
                                due_date: flatFinalDue || this.getDateDaysFromNow(30)
                            })
                        }
                    } else {
                        payments.push({
                            description: "Contract Payment",
                            amount: flatAmount,
                            direction: flatDirection,
                            due_date: flatFinalDue || this.getDateDaysFromNow(30)
                        })
                    }
                }
                break

            case "per_event":
                const perEventAmount = parseFloat(this.hasPerEventAmountTarget ? this.perEventAmountTarget.value : 0) || 0
                const perEventCount = parseInt(this.hasPerEventCountTarget ? this.perEventCountTarget.value : 1) || 1
                const perEventDirection = this.hasPerEventDirectionTarget ? this.perEventDirectionTarget.value : "incoming"
                const perEventTiming = this.hasPerEventTimingTarget ? this.perEventTimingTarget.value : "per_event"

                let totalAmount = perEventAmount * perEventCount

                // Apply discount if enabled
                const hasDiscount = this.hasPerEventDiscountTarget && this.perEventDiscountTarget.checked
                if (hasDiscount) {
                    const discountPercent = parseFloat(this.hasPerEventDiscountPercentTarget ? this.perEventDiscountPercentTarget.value : 0) || 0
                    if (discountPercent > 0) {
                        totalAmount = totalAmount * (1 - discountPercent / 100)
                    }
                }

                if (totalAmount > 0) {
                    if (perEventTiming === "upfront") {
                        const upfrontDue = this.hasPerEventUpfrontDueTarget ? this.perEventUpfrontDueTarget.value : ""
                        payments.push({
                            description: `${perEventCount} Events (Upfront)`,
                            amount: totalAmount,
                            direction: perEventDirection,
                            due_date: upfrontDue || this.getDateDaysFromNow(7)
                        })
                    } else {
                        // Create one payment entry summarizing per-event fees
                        payments.push({
                            description: `${perEventCount} Events @ $${perEventAmount.toFixed(2)} each`,
                            amount: totalAmount,
                            direction: perEventDirection,
                            due_date: this.getDateDaysFromNow(30)
                        })
                    }
                }
                break

            case "revenue_share":
                const ourShare = parseInt(this.hasRevenueOurShareTarget ? this.revenueOurShareTarget.value : 0) || 0
                const hasGuarantee = this.hasRevenueGuaranteeTarget && this.revenueGuaranteeTarget.checked
                const guaranteeAmount = parseFloat(this.hasRevenueGuaranteeAmountTarget ? this.revenueGuaranteeAmountTarget.value : 0) || 0

                if (ourShare > 0) {
                    payments.push({
                        description: `Revenue Share (${ourShare}% to venue)`,
                        amount: 0, // Amount TBD based on actual revenue
                        direction: "incoming",
                        due_date: this.getDateDaysFromNow(30)
                    })
                }
                if (hasGuarantee && guaranteeAmount > 0) {
                    payments.push({
                        description: "Minimum Guarantee",
                        amount: guaranteeAmount,
                        direction: "incoming",
                        due_date: this.getDateDaysFromNow(7)
                    })
                }
                break

            case "custom":
                // For custom, we already have the payments array managed manually
                return // Don't update, use the existing this.payments
        }

        this.payments = payments
        this.updateHiddenField()
    }
}
