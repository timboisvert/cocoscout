import { Controller } from "@hotwired/stimulus"

// The record page of a date change (Manage::DateChangesController#show):
// while CocoScout is still doing it, the progress frame reloads every two
// seconds, so each step is seen finishing. It stops once the frame says
// everything is done.
export default class extends Controller {
  static values = { finished: Boolean, every: { type: Number, default: 2000 } }

  connect() {
    if (!this.finishedValue) this.timer = setTimeout(() => this.reload(), this.everyValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  reload() {
    if (typeof this.element.reload === "function") this.element.reload()
  }
}
