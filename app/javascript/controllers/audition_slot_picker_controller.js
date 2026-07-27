import { Controller } from "@hotwired/stimulus"

// Open-signup slot picker: a horizontal, scrollable strip of date pills on top,
// and a slim list of that date's times below. Picking a date reveals its times;
// picking a time selects the underlying audition_session_id radio.
//
// Progressive enhancement: with JS off, the server renders the selected date's
// times visible, so single-date cycles work and multi-date ones still show one
// date's slots.
export default class extends Controller {
  static targets = ["dateTab", "timesGroup", "scroller", "leftArrow", "rightArrow"]

  connect() {
    const initial =
      this.dateTabTargets.find((t) => t.dataset.selected === "true") ||
      this.dateTabTargets[0]
    if (initial) this.activate(initial.dataset.date)

    this._onScrollOrResize = () => this.updateArrows()
    window.addEventListener("resize", this._onScrollOrResize)
    this.updateArrows()
  }

  disconnect() {
    window.removeEventListener("resize", this._onScrollOrResize)
  }

  selectDate(event) {
    this.activate(event.currentTarget.dataset.date)
  }

  activate(date) {
    this.dateTabTargets.forEach((tab) => {
      const on = tab.dataset.date === date
      tab.classList.toggle("bg-pink-500", on)
      tab.classList.toggle("text-white", on)
      tab.classList.toggle("border-pink-500", on)
      tab.classList.toggle("border-gray-200", !on)
      tab.classList.toggle("text-gray-700", !on)
      tab.setAttribute("aria-pressed", on ? "true" : "false")
    })
    this.timesGroupTargets.forEach((group) => {
      group.classList.toggle("hidden", group.dataset.date !== date)
    })
  }

  scrollLeft() {
    this.scrollerTarget.scrollBy({ left: -220, behavior: "smooth" })
  }

  scrollRight() {
    this.scrollerTarget.scrollBy({ left: 220, behavior: "smooth" })
  }

  updateArrows() {
    if (!this.hasScrollerTarget) return
    const el = this.scrollerTarget
    const overflowing = el.scrollWidth > el.clientWidth + 1
    const atStart = el.scrollLeft <= 0
    const atEnd = el.scrollLeft + el.clientWidth >= el.scrollWidth - 1
    if (this.hasLeftArrowTarget)
      this.leftArrowTarget.classList.toggle("hidden", !overflowing || atStart)
    if (this.hasRightArrowTarget)
      this.rightArrowTarget.classList.toggle("hidden", !overflowing || atEnd)
  }
}
