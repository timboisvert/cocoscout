import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        "description", "amount", "direction", "dueDate", "list", "paymentsJson", "structureJson",
        "summary", "totalIncoming", "totalOutgoing", "netAmount",
        // Flat fee targets
        "flatFeeConfig", "flatFeeAmount", "flatFeeDirection", "flatFeeDeposit",
        "flatFeeDepositConfig", "flatFeeDepositAmount", "flatFeeDepositPercent", "flatFeeDepositDue", "flatFeeFinalDue",
        // Per event targets
        "perEventConfig", "perEventAmount", "perEventDirection", "perEventDiscount",
        "perEventDiscountConfig", "perEventDiscountAfter", "perEventDiscountPercent", "perEventTerms",
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
    }

    toggleDeposit(event) {
        if (this.hasFlatFeeDepositConfigTarget) {
            this.flatFeeDepositConfigTarget.classList.toggle("hidden", !event.target.checked)
        }
    }

    toggleVolumeDiscount(event) {
        if (this.hasPerEventDiscountConfigTarget) {
            this.perEventDiscountConfigTarget.classList.toggle("hidden", !event.target.checked)
        }
    }

    toggleGuarantee(event) {
        if (this.hasRevenueGuaranteeConfigTarget) {
            this.revenueGuaranteeConfigTarget.classList.toggle("hidden", !event.target.checked)
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
        if (!this.hasSummaryTarget) return

        const incoming = this.payments
            .filter(p => p.direction === "incoming")
            .reduce((sum, p) => sum + p.amount, 0)

        const outgoing = this.payments
            .filter(p => p.direction === "outgoing")
            .reduce((sum, p) => sum + p.amount, 0)

        const net = incoming - outgoing

        if (this.hasTotalIncomingTarget) this.totalIncomingTarget.textContent = `$${incoming.toFixed(2)}`
        if (this.hasTotalOutgoingTarget) this.totalOutgoingTarget.textContent = `$${outgoing.toFixed(2)}`
        if (this.hasNetAmountTarget) {
            this.netAmountTarget.textContent = `$${Math.abs(net).toFixed(2)}`
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
}
