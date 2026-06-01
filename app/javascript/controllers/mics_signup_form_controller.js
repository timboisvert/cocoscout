import { Controller } from "@hotwired/stimulus"

// On the producer Sign-up form: show/hide the URL input depending on
// whether the chosen channel includes "online". In-person-only mics
// don't need a URL.
export default class extends Controller {
  static targets = ["channel", "urlBlock"]

  connect() { this.refresh() }

  refresh() {
    const v = this.hasChannelTarget ? this.channelTarget.value : ""
    const showUrl = (v === "online" || v === "online_and_in_person")
    if (this.hasUrlBlockTarget) {
      this.urlBlockTarget.classList.toggle("hidden", !showUrl)
    }
  }
}
