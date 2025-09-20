import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="clipboard"
export default class extends Controller {
  static targets = ["textField", "button"]

  copy(event) {
    const text = this.textFieldTarget.value
    const button = event?.currentTarget || this.buttonTarget
    navigator.clipboard.writeText(text)
      .then(() => {
        this.showCopiedIcon(button)
      })
      .catch((error) => {
        console.error("=== CLIPBOARD COPY FAILED ===", error)
      });
  }

  showCopiedIcon(button) {
    if (!button) return
    // Save original HTML
    if (!button._originalInnerHTML) {
      button._originalInnerHTML = button.innerHTML
    }
    // Swap to check icon
    button.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-6"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" /></svg>`
    button.classList.remove("bg-pink-500", "text-white")
    button.classList.add("bg-green-500", "text-white")
    setTimeout(() => {
      button.innerHTML = button._originalInnerHTML
      button.classList.remove("bg-green-500")
      button.classList.add("bg-pink-500", "text-white")
    }, 2000)
  }
}
