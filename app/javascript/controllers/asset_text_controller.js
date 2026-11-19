import { Controller } from "@hotwired/stimulus"

// A written item on a visual asset request (Tim, 2026-11-19), saved a
// moment after typing stops and again when the field is left. The server
// answers with the item's chip and the progress line redrawn.
export default class extends Controller {
  static targets = ["field", "status", "count"]
  static values = { url: String, max: Number }

  connect() {
    this.saved = this.fieldTarget.value
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  changed() {
    if (this.hasCountTarget && this.maxValue) {
      this.countTarget.textContent = `${this.fieldTarget.value.length} of ${this.maxValue} characters`
    }
    this.statusTarget.textContent = ""
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.save(), 900)
  }

  saveNow() {
    clearTimeout(this.timer)
    this.save()
  }

  async save() {
    const text = this.fieldTarget.value
    if (text === this.saved || this.fieldTarget.disabled) return

    this.statusTarget.textContent = "Saving"
    const body = { text }
    const name = document.getElementById("asset-uploader-name")?.value
    if (name) body.uploader_name = name

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: JSON.stringify(body)
      })
      const data = await response.json()
      if (!data.ok) {
        this.statusTarget.textContent = data.message
        return
      }
      this.saved = text
      this.statusTarget.textContent = "Saved a moment ago."
      const chip = this.element.querySelector("[id^='asset-text-chip-']")
      if (chip && data.card_html) chip.outerHTML = data.card_html
      const progress = document.getElementById("asset-progress")
      if (progress && data.progress_html) progress.outerHTML = data.progress_html
    } catch (_error) {
      this.statusTarget.textContent = "That didn't save. Check your connection, and it will try again when you type."
    }
  }
}
