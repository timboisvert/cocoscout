import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "ticketSalesFields",
    "flatFeeFields",
    "form",
    // Other Revenue targets
    "otherRevenueModal",
    "otherRevenueModalTitle",
    "otherRevenueDescription",
    "otherRevenueAmount",
    "otherRevenueEditIndex",
    "otherRevenueItems",
    "otherRevenueTotal",
    "otherRevenueEmpty",
    "otherRevenueTotalRow",
    // Expense targets
    "expenseModal",
    "expenseModalTitle",
    "expenseCategory",
    "expenseDescription",
    "expenseAmount",
    "expenseEditIndex",
    "expenseItems",
    "expensesTotal",
    "expensesEmpty",
    "expensesTotalRow",
    // Receipt targets
    "receiptModal",
    "receiptCurrentSection",
    "receiptCurrentLink",
    "receiptUploadLabel",
    "receiptFile",
    "receiptFileName",
    "receiptFileNameText",
    "receiptExpenseItemId",
    "receiptUploadButton",
    // Ticket Fees targets
    "ticketFeesSection",
    "ticketFeesTotal"
  ]

  connect() {
    this.otherRevenueItemCount = this.otherRevenueItemsTarget?.querySelectorAll('[data-line-item]').length || 0
    this.expenseItemCount = this.expenseItemsTarget?.querySelectorAll('[data-line-item]').length || 0
  }

  toggleRevenueType(event) {
    const revenueType = event.target.value

    if (revenueType === "flat_fee") {
      this.ticketSalesFieldsTarget.classList.add("hidden")
      this.flatFeeFieldsTarget.classList.remove("hidden")
      if (this.hasTicketFeesSectionTarget) {
        this.ticketFeesSectionTarget.classList.add("hidden")
      }
    } else {
      this.ticketSalesFieldsTarget.classList.remove("hidden")
      this.flatFeeFieldsTarget.classList.add("hidden")
      if (this.hasTicketFeesSectionTarget) {
        this.ticketFeesSectionTarget.classList.remove("hidden")
      }
    }
  }

  // Update ticket fees when checkboxes are changed
  updateTicketFees(event) {
    // Fees are calculated on form submit based on ticket count/revenue
    // This could be enhanced to show live calculations
  }

  // ===== Other Revenue Modal Methods =====

  openOtherRevenueModal(event) {
    if (event) event.preventDefault()
    this.otherRevenueEditIndexTarget.value = ""
    this.otherRevenueDescriptionTarget.value = ""
    this.otherRevenueAmountTarget.value = ""
    this.otherRevenueModalTitleTarget.textContent = "Add Revenue Item"
    this.otherRevenueModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    this.otherRevenueDescriptionTarget.focus()
  }

  closeOtherRevenueModal(event) {
    if (event) event.preventDefault()
    this.otherRevenueModalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  editOtherRevenueItem(event) {
    event.preventDefault()
    const button = event.currentTarget
    const index = button.dataset.index
    const description = button.dataset.description
    const amount = button.dataset.amount

    this.otherRevenueEditIndexTarget.value = index
    this.otherRevenueDescriptionTarget.value = description
    this.otherRevenueAmountTarget.value = amount
    this.otherRevenueModalTitleTarget.textContent = "Edit Revenue Item"
    this.otherRevenueModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    this.otherRevenueDescriptionTarget.focus()
  }

  saveOtherRevenueItem(event) {
    event.preventDefault()
    const description = this.otherRevenueDescriptionTarget.value.trim()
    const amount = parseFloat(this.otherRevenueAmountTarget.value) || 0
    const editIndex = this.otherRevenueEditIndexTarget.value

    if (!description || amount <= 0) {
      return // Don't save empty items
    }

    if (editIndex !== "") {
      // Update existing item
      this.updateOtherRevenueItemInList(parseInt(editIndex), description, amount)
    } else {
      // Add new item
      this.addOtherRevenueItemToList(description, amount)
    }

    this.closeOtherRevenueModal()
    this.updateOtherRevenueTotal()
    this.showOtherRevenueTotalRow()
  }

  addOtherRevenueItemToList(description, amount) {
    const index = this.otherRevenueItemCount++
    const html = this.buildOtherRevenueItemHtml(index, description, amount)

    // Hide the simple amount input if visible
    if (this.hasOtherRevenueEmptyTarget) {
      this.otherRevenueEmptyTarget.classList.add("hidden")
    }

    this.otherRevenueItemsTarget.insertAdjacentHTML('beforeend', html)
  }

  updateOtherRevenueItemInList(index, description, amount) {
    const item = this.otherRevenueItemsTarget.querySelector(`[data-line-item][data-index="${index}"]`)
    if (!item) return

    // Update display
    item.querySelector('p').textContent = description
    item.querySelector('.font-semibold').textContent = this.formatCurrency(amount)

    // Update hidden fields
    item.querySelector(`input[name*="[description]"]`).value = description
    item.querySelector(`input[name*="[amount]"]`).value = amount

    // Update data attributes on edit button
    const editButton = item.querySelector('[data-action*="editOtherRevenueItem"]')
    if (editButton) {
      editButton.dataset.description = description
      editButton.dataset.amount = amount
    }
  }

  removeOtherRevenueItem(event) {
    event.preventDefault()
    const button = event.currentTarget
    const index = button.dataset.index
    const item = this.otherRevenueItemsTarget.querySelector(`[data-line-item][data-index="${index}"]`)

    if (item) {
      item.remove()
      this.updateOtherRevenueTotal()

      // If no items left, show simple input and hide total row
      if (this.otherRevenueItemsTarget.querySelectorAll('[data-line-item]').length === 0) {
        if (this.hasOtherRevenueEmptyTarget) {
          this.otherRevenueEmptyTarget.classList.remove("hidden")
        }
        this.hideOtherRevenueTotalRow()
      }
    }
  }

  buildOtherRevenueItemHtml(index, description, amount) {
    return `
      <div class="flex items-center justify-between bg-gray-50 rounded-lg px-4 py-3" data-line-item data-index="${index}">
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium text-gray-900 truncate">${this.escapeHtml(description)}</p>
        </div>
        <div class="flex items-center gap-3">
          <span class="text-sm font-semibold text-gray-900">${this.formatCurrency(amount)}</span>
          <button type="button"
                  class="text-gray-400 hover:text-pink-600 p-1"
                  data-action="click->financials-form#editOtherRevenueItem"
                  data-index="${index}"
                  data-description="${this.escapeHtml(description)}"
                  data-amount="${amount}">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/>
            </svg>
          </button>
          <button type="button"
                  class="text-gray-400 hover:text-red-500 p-1"
                  data-action="click->financials-form#removeOtherRevenueItem"
                  data-index="${index}">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
            </svg>
          </button>
        </div>
        <input type="hidden" name="show_financials[other_revenue_details][${index}][description]" value="${this.escapeHtml(description)}">
        <input type="hidden" name="show_financials[other_revenue_details][${index}][amount]" value="${amount}">
      </div>
    `
  }

  updateOtherRevenueTotal() {
    const items = this.otherRevenueItemsTarget.querySelectorAll('[data-line-item]')
    let total = 0
    items.forEach(item => {
      const input = item.querySelector('input[name*="[amount]"]')
      total += parseFloat(input?.value) || 0
    })
    if (this.hasOtherRevenueTotalTarget) {
      this.otherRevenueTotalTarget.textContent = this.formatCurrency(total)
    }
  }

  showOtherRevenueTotalRow() {
    if (this.hasOtherRevenueTotalRowTarget) {
      this.otherRevenueTotalRowTarget.classList.remove("hidden")
    }
  }

  hideOtherRevenueTotalRow() {
    if (this.hasOtherRevenueTotalRowTarget) {
      this.otherRevenueTotalRowTarget.classList.add("hidden")
    }
  }

  // ===== Expense Modal Methods =====

  openExpenseModal(event) {
    if (event) event.preventDefault()
    this.expenseEditIndexTarget.value = ""
    if (this.hasExpenseCategoryTarget) {
      this.expenseCategoryTarget.value = "other"
    }
    this.expenseDescriptionTarget.value = ""
    this.expenseAmountTarget.value = ""
    this.expenseModalTitleTarget.textContent = "Add Expense Item"
    this.expenseModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    this.expenseCategoryTarget?.focus()
  }

  closeExpenseModal(event) {
    if (event) event.preventDefault()
    this.expenseModalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  editExpenseItem(event) {
    event.preventDefault()
    const button = event.currentTarget
    const index = button.dataset.index
    const category = button.dataset.category || "other"
    const description = button.dataset.description
    const amount = button.dataset.amount

    this.expenseEditIndexTarget.value = index
    if (this.hasExpenseCategoryTarget) {
      this.expenseCategoryTarget.value = category
    }
    this.expenseDescriptionTarget.value = description
    this.expenseAmountTarget.value = amount
    this.expenseModalTitleTarget.textContent = "Edit Expense Item"
    this.expenseModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    this.expenseCategoryTarget?.focus()
  }

  saveExpenseItem(event) {
    event.preventDefault()
    const category = this.hasExpenseCategoryTarget ? this.expenseCategoryTarget.value : "other"
    const description = this.expenseDescriptionTarget.value.trim()
    const amount = parseFloat(this.expenseAmountTarget.value) || 0
    const editIndex = this.expenseEditIndexTarget.value

    if (amount <= 0) {
      return // Don't save items with no amount
    }

    if (editIndex !== "") {
      // Update existing item
      this.updateExpenseItemInList(parseInt(editIndex), category, description, amount)
    } else {
      // Add new item
      this.addExpenseItemToList(category, description, amount)
    }

    this.closeExpenseModal()
    this.updateExpensesTotal()
    this.showExpensesTotalRow()
  }

  addExpenseItemToList(category, description, amount) {
    const index = this.expenseItemCount++
    const html = this.buildExpenseItemHtml(index, category, description, amount)

    // Hide the simple amount input if visible
    if (this.hasExpensesEmptyTarget) {
      this.expensesEmptyTarget.classList.add("hidden")
    }

    this.expenseItemsTarget.insertAdjacentHTML('beforeend', html)
  }

  updateExpenseItemInList(index, category, description, amount) {
    const item = this.expenseItemsTarget.querySelector(`[data-line-item][data-index="${index}"]`)
    if (!item) return

    // Build display text
    const categoryLabel = this.getCategoryLabel(category)
    const displayText = description ? `${categoryLabel}: ${description}` : categoryLabel

    // Update display - find the span with the text (inside the flex container)
    const textSpan = item.querySelector('span.text-gray-900.truncate') || item.querySelector('span.text-gray-900')
    if (textSpan) {
      textSpan.textContent = displayText
    }

    // Update amount display
    const amountSpan = item.querySelector('.font-medium.text-red-600')
    if (amountSpan) {
      amountSpan.textContent = this.formatCurrency(amount)
    }

    // Update hidden fields
    const categoryInput = item.querySelector(`input[name*="[category]"]`)
    const descriptionInput = item.querySelector(`input[name*="[description]"]`)
    const amountInput = item.querySelector(`input[name*="[amount]"]`)
    if (categoryInput) categoryInput.value = category
    if (descriptionInput) descriptionInput.value = description
    if (amountInput) amountInput.value = amount

    // Update data attributes on edit button
    const editButton = item.querySelector('[data-action*="editExpenseItem"]')
    if (editButton) {
      editButton.dataset.category = category
      editButton.dataset.description = description
      editButton.dataset.amount = amount
    }
  }

  removeExpenseItem(event) {
    event.preventDefault()
    event.stopPropagation()
    const button = event.currentTarget
    const index = button.dataset.index
    const expenseItemId = button.dataset.expenseItemId
    const item = this.expenseItemsTarget.querySelector(`[data-line-item][data-index="${index}"]`)

    if (item) {
      if (expenseItemId) {
        // For persisted records, add _destroy field instead of removing from DOM
        const destroyInput = document.createElement('input')
        destroyInput.type = 'hidden'
        destroyInput.name = `show_financials[expense_items_attributes][${index}][_destroy]`
        destroyInput.value = '1'
        item.appendChild(destroyInput)
        item.classList.add('hidden')
      } else {
        // For new items, just remove from DOM
        item.remove()
      }

      this.updateExpensesTotal()

      // If no visible items left, show simple input and hide total row
      const visibleItems = this.expenseItemsTarget.querySelectorAll('[data-line-item]:not(.hidden)')
      if (visibleItems.length === 0) {
        if (this.hasExpensesEmptyTarget) {
          this.expensesEmptyTarget.classList.remove("hidden")
        }
        this.hideExpensesTotalRow()
      }
    }
  }

  buildExpenseItemHtml(index, category, description, amount) {
    const categoryLabel = this.getCategoryLabel(category)
    const displayText = description ? `${categoryLabel}: ${this.escapeHtml(description)}` : categoryLabel

    return `
      <div class="flex items-center justify-between bg-white rounded-lg px-3 py-2" data-line-item data-index="${index}">
        <div class="flex items-center gap-2 flex-1 min-w-0">
          <span class="text-sm text-gray-900 truncate">${displayText}</span>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-sm font-medium text-red-600">${this.formatCurrency(amount)}</span>
          <button type="button"
                  class="text-gray-400 hover:text-pink-600 p-1"
                  data-action="click->financials-form#editExpenseItem"
                  data-index="${index}"
                  data-category="${category}"
                  data-description="${this.escapeHtml(description)}"
                  data-amount="${amount}">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/>
            </svg>
          </button>
          <button type="button"
                  class="text-gray-400 hover:text-red-500 p-1"
                  data-action="click->financials-form#removeExpenseItem"
                  data-index="${index}">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
          </button>
        </div>
        <input type="hidden" name="show_financials[expense_items_attributes][${index}][category]" value="${category}">
        <input type="hidden" name="show_financials[expense_items_attributes][${index}][description]" value="${this.escapeHtml(description)}">
        <input type="hidden" name="show_financials[expense_items_attributes][${index}][amount]" value="${amount}">
        <input type="hidden" name="show_financials[expense_items_attributes][${index}][position]" value="${index}">
      </div>
    `
  }

  updateExpensesTotal() {
    // Only count visible (non-deleted) items
    const items = this.expenseItemsTarget.querySelectorAll('[data-line-item]:not(.hidden)')
    let total = 0
    items.forEach(item => {
      const input = item.querySelector('input[name*="[amount]"]')
      total += parseFloat(input?.value) || 0
    })
    if (this.hasExpensesTotalTarget) {
      this.expensesTotalTarget.textContent = this.formatCurrency(total)
    }
  }

  showExpensesTotalRow() {
    if (this.hasExpensesTotalRowTarget) {
      this.expensesTotalRowTarget.classList.remove("hidden")
    }
  }

  hideExpensesTotalRow() {
    if (this.hasExpensesTotalRowTarget) {
      this.expensesTotalRowTarget.classList.add("hidden")
    }
  }

  // ===== Utility Methods =====

  stopPropagation(event) {
    event.stopPropagation()
  }

  closeWorksheet(event) {
    if (event) event.preventDefault()
    const worksheet = document.getElementById('financialWorksheet')
    if (worksheet) {
      worksheet.classList.add('hidden')
    }
  }

  formatCurrency(amount) {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount)
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text || ''
    return div.innerHTML
  }

  getCategoryLabel(category) {
    const labels = {
      venue: "Venue Rental",
      tech: "Tech/Equipment",
      marketing: "Marketing",
      supplies: "Supplies",
      travel: "Travel",
      food: "Food & Beverage",
      staff: "Staff/Crew",
      licensing: "Licensing/Rights",
      other: "Other"
    }
    return labels[category] || "Other"
  }

  // ===== Receipt Modal Methods =====

  openReceiptModal(event) {
    if (event) event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    const expenseItemId = button.dataset.expenseItemId
    const hasReceipt = button.dataset.hasReceipt === "true"

    this.receiptExpenseItemIdTarget.value = expenseItemId

    // Reset file input
    this.receiptFileTarget.value = ""
    this.receiptFileNameTarget.classList.add("hidden")

    // Show/hide current receipt section
    if (hasReceipt) {
      this.receiptCurrentSectionTarget.classList.remove("hidden")
      this.receiptCurrentLinkTarget.href = `/manage/money/expense_items/${expenseItemId}/receipt`
      this.receiptUploadLabelTarget.textContent = "Replace Receipt"
    } else {
      this.receiptCurrentSectionTarget.classList.add("hidden")
      this.receiptUploadLabelTarget.textContent = "Upload Receipt"
    }

    this.receiptModalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  closeReceiptModal(event) {
    if (event) event.preventDefault()
    this.receiptModalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  triggerReceiptFileInput(event) {
    event.preventDefault()
    this.receiptFileTarget.click()
  }

  handleReceiptSelect(event) {
    const file = event.target.files[0]
    if (file) {
      this.receiptFileNameTextTarget.textContent = file.name
      this.receiptFileNameTarget.classList.remove("hidden")
    } else {
      this.receiptFileNameTarget.classList.add("hidden")
    }
  }

  async uploadReceipt(event) {
    event.preventDefault()

    const file = this.receiptFileTarget.files[0]
    if (!file) {
      alert("Please select a file to upload")
      return
    }

    const expenseItemId = this.receiptExpenseItemIdTarget.value
    if (!expenseItemId) {
      alert("No expense item selected")
      return
    }

    // Disable button and show loading state
    const button = this.receiptUploadButtonTarget
    const originalText = button.textContent
    button.disabled = true
    button.textContent = "Uploading..."

    try {
      const formData = new FormData()
      formData.append("receipt", file)

      const csrfToken = document.querySelector('meta[name="csrf-token"]').content

      const response = await fetch(`/manage/money/expense_items/${expenseItemId}/upload_receipt`, {
        method: "POST",
        headers: {
          "X-CSRF-Token": csrfToken
        },
        body: formData
      })

      const result = await response.json()

      if (result.success) {
        // Reload the page to show the updated receipt icon
        window.location.reload()
      } else {
        alert(result.error || "Failed to upload receipt")
        button.disabled = false
        button.textContent = originalText
      }
    } catch (error) {
      console.error("Error uploading receipt:", error)
      alert("An error occurred while uploading")
      button.disabled = false
      button.textContent = originalText
    }
  }

  async removeReceipt(event) {
    event.preventDefault()

    if (!confirm("Remove this receipt?")) {
      return
    }

    const expenseItemId = this.receiptExpenseItemIdTarget.value
    if (!expenseItemId) {
      return
    }

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]').content

      const response = await fetch(`/manage/money/expense_items/${expenseItemId}/remove_receipt`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": csrfToken
        }
      })

      const result = await response.json()

      if (result.success) {
        // Reload the page to update the UI
        window.location.reload()
      } else {
        alert(result.error || "Failed to remove receipt")
      }
    } catch (error) {
      console.error("Error removing receipt:", error)
      alert("An error occurred")
    }
  }
}
