import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "backdrop", "name", "email", "headshot", "initials",
        "status", "amount", "date", "cancelForm", "refundForm",
        "confirmPanel", "actionPanel", "responseLink"]

    open(event) {
        event.preventDefault()
        event.stopPropagation()

        const el = event.currentTarget
        const name = el.dataset.registrantName
        const email = el.dataset.registrantEmail
        const headshotUrl = el.dataset.registrantHeadshot
        const initials = el.dataset.registrantInitials
        const status = el.dataset.registrantStatus
        const amount = el.dataset.registrantAmount
        const date = el.dataset.registrantDate
        const cancelUrl = el.dataset.registrantCancelUrl
        const refundUrl = el.dataset.registrantRefundUrl
        const canRefund = el.dataset.registrantCanRefund === "true"
        const responseUrl = el.dataset.registrantResponseUrl

        // Populate modal
        this.nameTarget.textContent = name
        this.emailTarget.textContent = email || "No email"

        if (headshotUrl) {
            this.headshotTarget.innerHTML = `<img src="${headshotUrl}" alt="${name}" class="w-16 h-16 rounded-lg object-cover">`
        } else {
            this.headshotTarget.innerHTML = `<div class="w-16 h-16 rounded-lg bg-gray-200 flex items-center justify-center text-gray-600 font-bold text-lg">${initials}</div>`
        }

        // Status badge
        const statusBadges = {
            confirmed: '<span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-700">Paid</span>',
            pending: '<span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-amber-100 text-amber-700">Pending</span>',
            refunded: '<span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-700">Refunded</span>',
            cancelled: '<span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-500">Cancelled</span>'
        }
        this.statusTarget.innerHTML = statusBadges[status] || status

        this.amountTarget.textContent = amount
        this.dateTarget.textContent = date

        // Set up form URLs
        this.cancelFormTarget.action = cancelUrl
        if (this.hasRefundFormTarget) {
            this.refundFormTarget.action = refundUrl
        }

        // Show/hide refund option based on status
        const refundSection = this.element.querySelector('[data-refund-section]')
        if (refundSection) {
            refundSection.classList.toggle('hidden', !canRefund)
        }
        const cancelSection = this.element.querySelector('[data-cancel-section]')
        if (cancelSection) {
            cancelSection.classList.toggle('hidden', status === 'refunded' || status === 'cancelled')
        }

        // Show/hide questionnaire response link
        if (this.hasResponseLinkTarget) {
            if (responseUrl) {
                this.responseLinkTarget.classList.remove('hidden')
                this.responseLinkTarget.href = responseUrl
            } else {
                this.responseLinkTarget.classList.add('hidden')
            }
        }

        // Reset to action panel
        this.showActionPanel()

        // Show modal
        this.modalTarget.classList.remove('hidden')
        this.backdropTarget.classList.remove('hidden')
    }

    close(event) {
        if (event) {
            event.preventDefault()
            event.stopPropagation()
        }
        this.modalTarget.classList.add('hidden')
        this.backdropTarget.classList.add('hidden')
    }

    showConfirmCancel(event) {
        event.preventDefault()
        this.actionPanelTarget.classList.add('hidden')
        this.confirmPanelTarget.classList.remove('hidden')
        this.confirmPanelTarget.dataset.action = 'cancel'
        this.confirmPanelTarget.querySelector('[data-confirm-title]').textContent = 'Remove Registrant'
        this.confirmPanelTarget.querySelector('[data-confirm-message]').textContent = 'This will remove them from the course without issuing a refund.'
        this.cancelFormTarget.classList.remove('hidden')
        if (this.hasRefundFormTarget) this.refundFormTarget.classList.add('hidden')
    }

    showConfirmRefund(event) {
        event.preventDefault()
        this.actionPanelTarget.classList.add('hidden')
        this.confirmPanelTarget.classList.remove('hidden')
        this.confirmPanelTarget.dataset.action = 'refund'
        this.confirmPanelTarget.querySelector('[data-confirm-title]').textContent = 'Refund & Remove'
        this.confirmPanelTarget.querySelector('[data-confirm-message]').textContent = 'This will issue a full refund via Stripe and remove them from the course.'
        if (this.hasRefundFormTarget) this.refundFormTarget.classList.remove('hidden')
        this.cancelFormTarget.classList.add('hidden')
    }

    showActionPanel() {
        if (this.hasActionPanelTarget) this.actionPanelTarget.classList.remove('hidden')
        if (this.hasConfirmPanelTarget) this.confirmPanelTarget.classList.add('hidden')
        this.cancelFormTarget.classList.add('hidden')
        if (this.hasRefundFormTarget) this.refundFormTarget.classList.add('hidden')
    }

    backdropClick(event) {
        if (event.target === this.backdropTarget) {
            this.close(event)
        }
    }
}
