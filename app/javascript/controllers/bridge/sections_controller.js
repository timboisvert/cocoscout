import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Bridge Component: in the app, a page's Section row (shared/section_picker)
// opens the phone's own menu in place of our sheet (Tim, 2026-11-20). Only
// app builds that register "sections" load this; everything else, mobile
// web and older installs included, keeps the sheet.
//
// The page tells the app where the row is and what the sections are; the app
// answers with the one picked, and we click that section's row in the sheet,
// so a pick does exactly what the sheet's row does.
//   iPhone: the app lays its own button over the row ("connect"), so a tap
//           opens the menu from it. A tap that reaches the page anyway opens
//           the sheet as before.
//   Android: the page takes the tap and asks for the menu ("open").
export default class extends BridgeComponent {
  static component = "sections"
  static targets = ["row", "item"]

  connect() {
    super.connect()
    this.announce = this.announce.bind(this)
    this.later = () => { clearTimeout(this.timer); this.timer = setTimeout(this.announce, 80) }
    // The row moves when anything above it changes height.
    this.observer = new ResizeObserver(this.later)
    this.observer.observe(document.body)
    window.addEventListener("resize", this.later)
    this.announce()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.observer?.disconnect()
    window.removeEventListener("resize", this.later)
    this.send("disconnect")
    super.disconnect()
  }

  // Android: the tap on the row.
  open(event) {
    if (!this.android || !this.hasRowTarget) return
    event.preventDefault()
    event.stopImmediatePropagation()
    this.send("open", this.message, reply => this.choose(reply.data.index))
  }

  announce() {
    if (!this.hasRowTarget || this.rowTarget.offsetParent === null) return this.send("disconnect")
    if (this.android) return
    this.send("connect", this.message, reply => this.choose(reply.data.index))
  }

  choose(index) {
    this.itemTargets[index]?.click()
    // The check mark moves on a page whose sections are panels.
    this.later()
  }

  get android() { return /Android/i.test(navigator.userAgent) }

  // { rect: where the row is on the page, groups: [{ title, items: [{ index, title, selected, danger, locked }] }] }
  get message() {
    const box = this.rowTarget.getBoundingClientRect()
    const groups = []
    this.itemTargets.forEach((item, index) => {
      if (item.classList.contains("hidden")) return
      const title = item.dataset.sectionGroup || ""
      let group = groups[groups.length - 1]
      if (!group || group.title !== title) groups.push(group = { title, items: [] })
      group.items.push({
        index,
        title: item.querySelector("[data-section-name] span")?.textContent.trim() || item.textContent.trim(),
        selected: item.hasAttribute("aria-current"),
        danger: item.dataset.sectionDanger === "true",
        locked: item.dataset.sectionLocked === "true"
      })
    })
    return {
      rect: { x: box.left + window.scrollX, y: box.top + window.scrollY, width: box.width, height: box.height },
      groups
    }
  }
}
