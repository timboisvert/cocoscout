import { Controller } from "@hotwired/stimulus"

// The record page of a date change (Manage::DateChangesController#show):
// while CocoScout is still doing it, the progress frame reloads every two
// seconds, so each step is seen finishing.
//
// This sits on an element INSIDE the frame, not on the frame: a frame keeps
// its own element and attributes when it reloads and only its contents are
// replaced, so a controller on the frame would connect once, with the first
// answer's "finished", and never again. Inside, every reload connects a new
// one that reads the fresh value, and the reloading stops by itself once the
// contents say everything is done.
export default class extends Controller {
  static values = { finished: Boolean, every: { type: Number, default: 2000 } }

  connect() {
    if (!this.finishedValue) this.timer = setTimeout(() => this.reload(), this.everyValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  reload() {
    const frame = this.element.closest("turbo-frame")
    if (frame && typeof frame.reload === "function") frame.reload()
  }
}
