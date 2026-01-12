import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "ticketSalesFields",
    "flatFeeFields",
    "form",
    "otherRevenueSimple",
    "otherRevenueDetailed",
    "otherRevenueItems",
    "otherRevenueTotal",
    "expensesSimple",
    "expensesDetailed",
    "expensesItems",
    "expensesTotal"
  ]

  connect() {
    this.otherRevenueItemCount = this.otherRevenueItemsTarget?.querySelectorAll('[data-line-item]').length || 0
    this.expenseItemCount = this.expensesItemsTarget?.querySelectorAll('[data-line-item]').length || 0
  }

  toggleRevenueType(event) {
    const revenueType = event.target.value

    if (revenueType === "flat_fee") {
      this.ticketSalesFieldsTarget.classList.add("hidden")
      this.flatFeeFieldsTarget.classList.remove("hidden")
    } else {
      this.ticketSalesFieldsTarget.classList.remove("hidden")
      this.flatFeeFieldsTarget.classList.add("hidden")
    }
  }

  // Toggle between simple amount and detailed line items for Other Revenue
  toggleOtherRevenueMode(event) {
    event.preventDefault()
    const isDetailed = !this.otherRevenueDetailedTarget.classList.contains("hidden")

    if (isDetailed) {
      // Switch to simple mode
      this.otherRevenueSimpleTarget.classList.remove("hidden")
      this.otherRevenueDetailedTarget.classList.add("hidden")
    } else {
      // Switch to detailed mode
      this.otherRevenueSimpleTarget.classList.add("hidden")
      this.otherRevenueDetailedTarget.classList.remove("hidden")
      // Add first item if none exist
      if (this.otherRevenueItemCount === 0) {
        this.addOtherRevenueItem()
      }
    }
  }

  // Toggle between simple amount and detailed line items for Expenses
  toggleExpensesMode(event) {
    event.preventDefault()
    const isDetailed = !this.expensesDetailedTarget.classList.contains("hidden")

    if (isDetailed) {
      // Switch to simple mode
      this.expensesSimpleTarget.classList.remove("hidden")
      this.expensesDetailedTarget.classList.add("hidden")
    } else {
      // Switch to detailed mode
      this.expensesSimpleTarget.classList.add("hidden")
      this.expensesDetailedTarget.classList.remove("hidden")
      // Add first item if none exist
      if (this.expenseItemCount === 0) {
        this.addExpenseItem()
      }
    }
  }

  addOtherRevenueItem(event) {
    if (event) event.preventDefault()
    const index = this.otherRevenueItemCount++
    const html = this.buildLineItemHtml('other_revenue_details', index)
    this.otherRevenueItemsTarget.insertAdjacentHTML('beforeend', html)
    // Focus the description field
    const newItem = this.otherRevenueItemsTarget.lastElementChild
    newItem.querySelector('input[type="text"]')?.focus()
  }

  addExpenseItem(event) {
    if (event) event.preventDefault()
    const index = this.expenseItemCount++
    const html = this.buildLineItemHtml('expense_details', index)
    this.expensesItemsTarget.insertAdjacentHTML('beforeend', html)
    // Focus the description field
    const newItem = this.expensesItemsTarget.lastElementChild
    newItem.querySelector('input[type="text"]')?.focus()
  }

  removeLineItem(event) {
    event.preventDefault()
    const item = event.target.closest('[data-line-item]')
    if (item) {
      item.remove()
      this.updateOtherRevenueTotal()
      this.updateExpensesTotal()
    }
  }

  updateOtherRevenueTotal() {
    const items = this.otherRevenueItemsTarget.querySelectorAll('[data-line-item]')
    let total = 0
    items.forEach(item => {
      const input = item.querySelector('input[type="number"]')
      total += parseFloat(input?.value) || 0
    })
    this.otherRevenueTotalTarget.textContent = this.formatCurrency(total)
  }

  updateExpensesTotal() {
    const items = this.expensesItemsTarget.querySelectorAll('[data-line-item]')
    let total = 0
    items.forEach(item => {
      const input = item.querySelector('input[type="number"]')
      total += parseFloat(input?.value) || 0
    })
    this.expensesTotalTarget.textContent = this.formatCurrency(total)
  }

  buildLineItemHtml(fieldName, index) {
    return `
      <div data-line-item class="flex items-center gap-2 bg-gray-50 rounded-lg p-3">
        <input type="text"
               name="show_financials[${fieldName}][${index}][description]"
               placeholder="Description"
               class="flex-1 rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-pink-500 focus:ring-pink-500">
        <div class="relative w-28">
          <span class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500 text-sm">$</span>
          <input type="number"
                 name="show_financials[${fieldName}][${index}][amount]"
                 min="0"
                 step="0.01"
                 placeholder="0.00"
                 data-action="input->financials-form#${fieldName === 'other_revenue_details' ? 'updateOtherRevenueTotal' : 'updateExpensesTotal'}"
                 class="w-full rounded-lg border border-gray-300 pl-7 pr-3 py-2 text-sm focus:border-pink-500 focus:ring-pink-500">
        </div>
        <button type="button"
                data-action="click->financials-form#removeLineItem"
                class="text-gray-400 hover:text-red-500 p-1">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
          </svg>
        </button>
      </div>
    `
  }

  formatCurrency(amount) {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount)
  }
}
