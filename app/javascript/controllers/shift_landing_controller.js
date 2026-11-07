import { Controller } from "@hotwired/stimulus"

// A shift notice links to My Shifts with #shift-<id>. A lit row below the
// fold helps nobody, so on arrival: scroll the row to the middle of the
// screen (clear of the fixed top bar), light it for a moment, and open its
// sheet. A link to a shift that's gone lands at the top of the list.
// Deferred a tick so the sheet's own controller is connected first.
export default class extends Controller {
  connect() {
    requestAnimationFrame(() => this.land())
  }

  land() {
    const match = (window.location.hash || "").match(/^#shift-(\d+)$/)
    if (!match) return
    const row = this.element.querySelector(`#shift-${match[1]}`)
    if (!row) return

    row.scrollIntoView({ block: "center", behavior: "smooth" })
    const background = row.style.backgroundColor
    const shadow = row.style.boxShadow
    row.style.backgroundColor = "#fdf2f8"
    row.style.boxShadow = "inset 3px 0 0 #ec4899"
    setTimeout(() => {
      row.style.backgroundColor = background
      row.style.boxShadow = shadow
    }, 2500)

    const trigger = row.querySelector("[data-modal-id]")
    if (trigger) setTimeout(() => trigger.click(), 450)
    // Once is enough: a reload or a back-navigation shouldn't open it again.
    history.replaceState(null, "", window.location.pathname + window.location.search)
  }
}
