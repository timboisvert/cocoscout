import { Controller } from "@hotwired/stimulus"

// Copies a piece of text and says so on the button for a moment.
//   <span data-controller="copy-text" data-copy-text-text-value="a@b.c, d@e.f">
//     <button data-action="click->copy-text#copy">Copy addresses</button>
//   </span>
export default class extends Controller {
  static values = { text: String, done: { type: String, default: "Copied" } }

  copy(event) {
    const button = event.currentTarget
    navigator.clipboard.writeText(this.textValue).then(() => {
      if (button.dataset.copyTextWas) return
      button.dataset.copyTextWas = button.textContent
      button.textContent = this.doneValue
      setTimeout(() => {
        button.textContent = button.dataset.copyTextWas
        delete button.dataset.copyTextWas
      }, 2000)
    })
  }
}
