import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "slotName", "slotInfo", "hiddenSlotId", "confirmButton", "changeSlotSection", "formSection", "slotList", "lockedSlot"]
  static values = {
    submitUrl: String,
    changeMode: Boolean
  }

  connect() {
    this.keyHandler = this.handleKeydown.bind(this)
  }

  disconnect() {
    document.removeEventListener('keydown', this.keyHandler)
  }

  handleKeydown(event) {
    if (event.key === 'Escape') {
      this.close()
    }
  }

  switchToChangeSlot(event) {
    event.preventDefault()

    // Enable change mode
    this.changeModeValue = true

    // Hide the "already registered" section
    if (this.hasChangeSlotSectionTarget) {
      this.changeSlotSectionTarget.classList.add('hidden')
    }

    // Convert locked slots to clickable buttons
    this.lockedSlotTargets.forEach(lockedSlot => {
      const slotId = lockedSlot.dataset.slotId
      const slotName = lockedSlot.dataset.slotName
      const spotsRemaining = lockedSlot.dataset.spotsRemaining
      const capacity = lockedSlot.dataset.capacity

      // Create a button to replace the div
      const button = document.createElement('button')
      button.type = 'button'
      button.dataset.action = 'click->sign-up-confirmation#selectSlot'
      button.dataset.slotId = slotId
      button.dataset.slotName = slotName
      button.dataset.spotsRemaining = spotsRemaining
      button.dataset.capacity = capacity
      button.className = 'w-full flex items-center justify-between py-3 px-4 bg-white border border-gray-200 rounded-lg cursor-pointer hover:border-pink-300 hover:bg-pink-50 transition-colors text-left group'
      button.innerHTML = lockedSlot.innerHTML

      // Update text styling for hover
      const nameSpan = button.querySelector('span.text-gray-600')
      if (nameSpan) {
        nameSpan.classList.remove('text-gray-600')
        nameSpan.classList.add('text-gray-900', 'font-medium', 'group-hover:text-pink-700')
      }

      lockedSlot.replaceWith(button)
    })

    // Scroll to and highlight the slot list
    if (this.hasSlotListTarget) {
      // Add highlight effect
      this.slotListTarget.classList.add('ring-2', 'ring-pink-500', 'ring-offset-2')

      // Scroll into view smoothly
      this.slotListTarget.scrollIntoView({ behavior: 'smooth', block: 'center' })

      // Remove highlight after a moment
      setTimeout(() => {
        this.slotListTarget.classList.remove('ring-2', 'ring-pink-500', 'ring-offset-2')
      }, 2000)
    }
  }

  openCancelConfirmation(event) {
    event.preventDefault()

    if (confirm('Are you sure you want to cancel your registration? This action cannot be undone.')) {
      this.performCancelRegistration()
    }
  }

  performCancelRegistration() {
    const codeMatch = window.location.pathname.match(/\/signups\/([^\/]+)/)
    const code = codeMatch ? codeMatch[1] : null

    if (!code) {
      console.error('Could not determine sign-up form code')
      return
    }

    const form = document.createElement('form')
    form.method = 'POST'
    form.action = `/my/signups/${code}/cancel`

    const csrfToken = document.querySelector('[name="csrf-token"]')?.content
    if (csrfToken) {
      const tokenInput = document.createElement('input')
      tokenInput.type = 'hidden'
      tokenInput.name = 'authenticity_token'
      tokenInput.value = csrfToken
      form.appendChild(tokenInput)
    }

    document.body.appendChild(form)
    form.submit()
  }

  showNotification(message, type = 'success') {
    const notice = document.createElement('div')
    notice.className = `mb-4 p-4 rounded-lg ${type === 'success' ? 'bg-green-50 text-green-800 border border-green-200' : 'bg-blue-50 text-blue-800 border border-blue-200'}`
    notice.innerHTML = `<p class="text-sm font-medium">${message}</p>`

    const container = document.querySelector('[data-controller="sign-up-confirmation"]')
    if (container) {
      container.insertBefore(notice, container.firstChild)
      setTimeout(() => notice.remove(), 3000)
    }
  }

  selectSlot(event) {
    event.preventDefault()

    const slotId = event.currentTarget.dataset.slotId
    const slotName = event.currentTarget.dataset.slotName
    const spotsRemaining = event.currentTarget.dataset.spotsRemaining
    const capacity = event.currentTarget.dataset.capacity

    // Update modal content (targets may not exist for waitlist modes)
    if (this.hasSlotNameTarget) {
      this.slotNameTarget.textContent = slotName
    }
    this.hiddenSlotIdTarget.value = slotId

    // Show spots info if capacity > 1
    if (this.hasSlotInfoTarget) {
      if (parseInt(capacity) > 1) {
        this.slotInfoTarget.textContent = `${spotsRemaining} spot${spotsRemaining === '1' ? '' : 's'} remaining`
        this.slotInfoTarget.classList.remove('hidden')
      } else {
        this.slotInfoTarget.classList.add('hidden')
      }
    }

    // Show modal
    this.modalTarget.classList.remove('hidden')
    document.addEventListener('keydown', this.keyHandler)

    // Focus confirm button for accessibility
    setTimeout(() => this.confirmButtonTarget.focus(), 100)
  }

  close(event) {
    if (event) event.preventDefault()
    this.modalTarget.classList.add('hidden')
    document.removeEventListener('keydown', this.keyHandler)
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  confirm(event) {
    event.preventDefault()

    // Disable the button and show loading state
    this.confirmButtonTarget.disabled = true
    this.confirmButtonTarget.innerHTML = `
      <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white inline" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
      Confirming...
    `

    // Submit the form
    const form = this.confirmButtonTarget.closest('form')
    if (form) {
      form.submit()
    }
  }
}
