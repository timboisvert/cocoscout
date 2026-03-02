import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    togglePaymentRemoval(event) {
        const checkbox = event.target
        const paymentRow = checkbox.closest('[class*="flex items-center justify-between"]')

        if (checkbox.checked) {
            paymentRow.classList.remove('bg-gray-50')
            paymentRow.classList.add('bg-red-50', 'border', 'border-red-200')

            // Strike through the description
            const description = paymentRow.querySelector('.font-medium')
            if (description) {
                description.classList.add('line-through', 'text-gray-500')
            }

            // Update status to show "Will be removed"
            const statusContainer = paymentRow.querySelector('.text-xs:last-child')
            if (statusContainer) {
                statusContainer.innerHTML = `
          <span class="inline-flex items-center gap-1 text-red-600">
            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
            </svg>
            Will be removed
          </span>
        `
            }
        } else {
            paymentRow.classList.add('bg-gray-50')
            paymentRow.classList.remove('bg-red-50', 'border', 'border-red-200')

            // Remove strike through
            const description = paymentRow.querySelector('.font-medium')
            if (description) {
                description.classList.remove('line-through', 'text-gray-500')
            }

            // Restore "Pending" status
            const statusContainer = paymentRow.querySelector('.text-xs:last-child')
            if (statusContainer) {
                statusContainer.innerHTML = '<span class="text-yellow-600">Pending</span>'
            }
        }
    }
}
