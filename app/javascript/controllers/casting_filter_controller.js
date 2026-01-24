import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle(event) {
    const button = event.currentTarget
    const isCurrentlyActive = button.getAttribute("aria-checked") === "true"
    const newState = !isCurrentlyActive

    // Update URL with the new state
    const url = new URL(window.location.href)
    url.searchParams.set("hide_canceled", newState.toString())
    
    Turbo.visit(url.toString())
  }
}
