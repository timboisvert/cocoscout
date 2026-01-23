import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["showName", "slotName", "registrationName"]

  openModal(event) {
    event.preventDefault()

    const button = event.currentTarget
    // Get the button's dataset which should have our data attributes
    const dataset = button.dataset

    // Extract values from data attributes
    const registrationId = dataset.registrationId
    const registrationName = dataset.registrationName
    const slotName = dataset.slotName
    const showName = dataset.showName
    const formId = dataset.formId
    const productionId = dataset.productionId

    // Store data for later use
    this.registrationId = registrationId
    this.formId = formId
    this.productionId = productionId

    // Populate modal content
    this.showNameTarget.textContent = showName
    this.slotNameTarget.textContent = slotName
    this.registrationNameTarget.textContent = registrationName

    // Show modal
    const modal = document.getElementById("removeRegistrationModal")
    modal.classList.remove("hidden")
  }

  closeModal(event) {
    if (event) event.preventDefault()
    const modal = document.getElementById("removeRegistrationModal")
    modal.classList.add("hidden")
  }

  confirmRemove(event) {
    event.preventDefault()

    // Create and submit deletion form
    const form = document.createElement("form")
    form.method = "POST"
    form.action = `/manage/signups/forms/${this.productionId}/${this.formId}/cancel_registration/${this.registrationId}`

    // Add CSRF token
    const csrfToken = document.querySelector("[name='csrf-token']")?.content
    if (csrfToken) {
      const tokenInput = document.createElement("input")
      tokenInput.type = "hidden"
      tokenInput.name = "authenticity_token"
      tokenInput.value = csrfToken
      form.appendChild(tokenInput)
    }

    // Add Turbo method override
    const methodInput = document.createElement("input")
    methodInput.type = "hidden"
    methodInput.name = "_method"
    methodInput.value = "DELETE"
    form.appendChild(methodInput)

    document.body.appendChild(form)
    form.submit()
  }
}
