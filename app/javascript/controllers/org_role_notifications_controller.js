import { Controller } from "@hotwired/stimulus"

// Handles the interaction between global role dropdown and notifications toggle
// When switching to manager, automatically enables notifications if they're off
export default class extends Controller {
  static targets = ["roleSelect", "toggle", "hiddenField"]

  roleChanged(event) {
    const newRole = event.target.value
    
    // If switching to manager and notifications are off, turn them on
    if (newRole === "manager" && this.hiddenFieldTarget.value === "0") {
      this.enableNotifications()
    }
  }

  toggleNotifications() {
    const isCurrentlyEnabled = this.hiddenFieldTarget.value === "1"
    
    if (isCurrentlyEnabled) {
      this.disableNotifications()
    } else {
      this.enableNotifications()
    }
    
    // Submit the form
    this.hiddenFieldTarget.closest("form").requestSubmit()
  }

  enableNotifications() {
    this.hiddenFieldTarget.value = "1"
    this.toggleTarget.classList.remove("bg-gray-200")
    this.toggleTarget.classList.add("bg-pink-500")
    this.toggleTarget.setAttribute("aria-checked", "true")
    const knob = this.toggleTarget.querySelector("span")
    knob.classList.remove("translate-x-0")
    knob.classList.add("translate-x-5")
  }

  disableNotifications() {
    this.hiddenFieldTarget.value = "0"
    this.toggleTarget.classList.remove("bg-pink-500")
    this.toggleTarget.classList.add("bg-gray-200")
    this.toggleTarget.setAttribute("aria-checked", "false")
    const knob = this.toggleTarget.querySelector("span")
    knob.classList.remove("translate-x-5")
    knob.classList.add("translate-x-0")
  }
}
