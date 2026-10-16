import { Controller } from "@hotwired/stimulus"
import { confirmDialog } from "controllers/lib/confirm_dialog"

export default class extends Controller {
  static targets = ["modal", "slotName", "slotInfo", "hiddenSlotId", "confirmButton", "changeSlotSection", "formSection", "slotList", "lockedSlot", "modalTitle", "modalForm", "details"]
  static values = {
    submitUrl: String,
    changeMode: Boolean,
    changeSlotUrl: String
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

  async openCancelConfirmation(event) {
    event.preventDefault()

    if (await confirmDialog({ title: "Cancel registration?", message: "Are you sure you want to cancel your registration? This action cannot be undone.", confirmText: "Cancel registration", cancelText: "Keep registration" })) {
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

  changeSlot(event) {
    event.preventDefault()

    const slotId = event.currentTarget.dataset.slotId
    const slotName = event.currentTarget.dataset.slotName
    const spotsRemaining = event.currentTarget.dataset.spotsRemaining
    const capacity = event.currentTarget.dataset.capacity

    // Update modal for change mode
    this.changeModeValue = true

    if (this.hasModalTitleTarget) {
      this.modalTitleTarget.textContent = 'Change Your Slot'
    }

    if (this.hasConfirmButtonTarget) {
      this.confirmButtonTarget.textContent = 'Confirm Change'
    }

    // Update modal content
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

    // Update form action if we have the target
    if (this.hasModalFormTarget && this.hasChangeSlotUrlValue) {
      this.modalFormTarget.action = this.changeSlotUrlValue
    }

    // Show modal
    this.modalTarget.classList.remove('hidden')
    document.addEventListener('keydown', this.keyHandler)

    // Focus confirm button for accessibility
    setTimeout(() => this.confirmButtonTarget.focus(), 100)
  }

  // The details form (guest name, the form's questions) is never sent by
  // itself: Enter in one of its fields mustn't post it anywhere.
  holdSubmit(event) {
    event.preventDefault()
  }

  // Whether the details form is filled in well enough to sign up; if not,
  // shows what's missing. The browser checks typed fields and yes/no; a
  // required pick-one, pick-several or file question has no check of its own.
  detailsReady() {
    if (!this.hasDetailsTarget) return true
    if (!this.detailsTarget.reportValidity()) return false

    const unanswered = Array.from(this.detailsTarget.querySelectorAll('[data-required-answer]')).find(group => !this.answered(group))
    if (!unanswered) return true

    const note = unanswered.querySelector('[data-required-note]')
    note?.classList.remove('hidden')
    unanswered.scrollIntoView({ behavior: 'smooth', block: 'center' })
    unanswered.addEventListener('change', () => note?.classList.add('hidden'), { once: true })
    return false
  }

  answered(group) {
    return Array.from(group.querySelectorAll('input, textarea, select')).some(field => {
      if (field.type === 'file') return field.files.length > 0
      if (field.type === 'checkbox' || field.type === 'radio') return field.checked
      return field.value.trim() !== ''
    })
  }

  // Copies the details form's fields, files too, into the form being sent.
  copyDetails(form) {
    if (!this.hasDetailsTarget) return

    form.querySelectorAll('[data-copied-detail]').forEach(field => field.remove())
    for (const [name, value] of new FormData(this.detailsTarget)) {
      const field = document.createElement('input')
      field.name = name
      field.dataset.copiedDetail = ''
      if (value instanceof File) {
        if (!value.name) continue // a file field left empty
        const files = new DataTransfer()
        files.items.add(value)
        field.type = 'file'
        field.hidden = true
        field.files = files.files
      } else {
        field.type = 'hidden'
        field.value = value
      }
      form.appendChild(field)
    }
    form.enctype = 'multipart/form-data'
  }

  selectSlot(event) {
    event.preventDefault()
    if (!this.detailsReady()) return

    const slotId = event.currentTarget.dataset.slotId
    const slotName = event.currentTarget.dataset.slotName
    const spotsRemaining = event.currentTarget.dataset.spotsRemaining
    const capacity = event.currentTarget.dataset.capacity

    // Reset to normal mode (not change mode)
    this.changeModeValue = false

    if (this.hasModalTitleTarget) {
      this.modalTitleTarget.textContent = 'Confirm Sign-Up'
    }

    if (this.hasConfirmButtonTarget) {
      this.confirmButtonTarget.textContent = 'Confirm Sign-Up'
    }

    // Reset form action to original submit URL if available
    if (this.hasModalFormTarget && this.hasSubmitUrlValue) {
      this.modalFormTarget.action = this.submitUrlValue
    }

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

    // Submit the form, with the details unless it's moving a slot
    const form = this.confirmButtonTarget.closest('form')
    if (form) {
      if (!this.changeModeValue) this.copyDetails(form)
      form.submit()
    }
  }

  joinQueue(event) {
    event.preventDefault()
    if (!this.detailsReady()) return

    const button = event.currentTarget
    button.disabled = true
    button.innerHTML = `
      <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white inline" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
      Joining Queue...
    `

    // Submit to the queue endpoint
    const form = document.createElement('form')
    form.method = 'POST'
    form.action = this.submitUrlValue

    const csrfToken = document.querySelector('[name="csrf-token"]')?.content
    if (csrfToken) {
      const tokenInput = document.createElement('input')
      tokenInput.type = 'hidden'
      tokenInput.name = 'authenticity_token'
      tokenInput.value = csrfToken
      form.appendChild(tokenInput)
    }

    this.copyDetails(form)

    document.body.appendChild(form)
    form.submit()
  }
}
