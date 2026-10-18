import { Controller } from "@hotwired/stimulus"

// The production ticket page's date picker (Tim, 2026-10-18): the chosen date
// is a card with Change date; pressing it hides the card and shows the list
// of dates in its place, and Close brings the card back. With no date chosen
// yet the list is open and there is no card or Close (the page renders it so).
export default class extends Controller {
  static targets = ["card", "list"]

  open() {
    this.cardTarget.classList.add("hidden")
    this.listTarget.classList.remove("hidden")
    this.listTarget.querySelector("a, button")?.focus()
  }

  close() {
    this.listTarget.classList.add("hidden")
    this.cardTarget.classList.remove("hidden")
  }
}
