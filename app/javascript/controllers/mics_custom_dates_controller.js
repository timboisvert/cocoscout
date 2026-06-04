import { Controller } from "@hotwired/stimulus"

// Manages a list of explicit date+time pairs for the "Custom dates"
// recurrence. We serialize the full list as JSON into a single hidden
// `mic[custom_dates_json]` input on every change — server parses it and
// stores into the `custom_dates` jsonb column. This sidesteps strong
// params headaches with nested arrays of hashes.
export default class extends Controller {
  static targets = ["datePicker", "timePicker", "list", "empty", "store"]
  static values  = { initial: Array }

  connect() {
    const normalize = (entry) => {
      if (typeof entry === "string") return { date: entry, time: "" }
      if (entry && typeof entry === "object") return { date: entry.date || "", time: entry.time || "" }
      return null
    }
    this.entries = (this.initialValue || [])
      .map(normalize).filter(e => e && e.date)
    this.sort()
    this.render()
  }

  add(e) {
    e?.preventDefault()
    const date = this.datePickerTarget.value
    const time = this.timePickerTarget.value
    if (!date) return
    // De-dupe on (date, time) so the same entry can't be added twice.
    if (!this.entries.some(x => x.date === date && x.time === time)) {
      this.entries.push({ date, time })
      this.sort()
    }
    this.datePickerTarget.value = ""
    this.timePickerTarget.value = ""
    this.render()
  }

  remove(e) {
    e.preventDefault()
    const idx = parseInt(e.currentTarget.dataset.idx, 10)
    if (Number.isInteger(idx)) {
      this.entries.splice(idx, 1)
      this.render()
    }
  }

  sort() {
    this.entries.sort((a, b) => {
      const da = a.date + " " + (a.time || "")
      const db = b.date + " " + (b.time || "")
      return da.localeCompare(db)
    })
  }

  render() {
    if (!this.hasListTarget) return
    this.listTarget.innerHTML = ""
    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", this.entries.length > 0)
    if (this.hasStoreTarget) this.storeTarget.value = JSON.stringify(this.entries)

    this.entries.forEach((entry, i) => {
      const pill = document.createElement("span")
      pill.className = "inline-flex items-center gap-1.5 px-3 py-1.5 bg-pink-50 border border-pink-200 text-pink-700 text-sm rounded mr-1.5 mb-1.5"
      const label = document.createElement("span")
      label.textContent = this.formatLabel(entry)
      const x = document.createElement("button")
      x.type = "button"
      x.className = "text-pink-400 hover:text-pink-700 cursor-pointer text-base leading-none"
      x.textContent = "×"
      x.dataset.idx = i
      x.dataset.action = "click->mics-custom-dates#remove"
      pill.appendChild(label)
      pill.appendChild(x)
      this.listTarget.appendChild(pill)
    })
  }

  formatLabel({ date, time }) {
    const [y, m, d] = date.split("-").map(n => parseInt(n, 10))
    const dateObj = new Date(y, m - 1, d)
    const datePart = dateObj.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" })
    if (!time) return `${datePart} · no time`
    return `${datePart} · ${this.formatTime(time)}`
  }

  formatTime(hhmm) {
    const [h, m] = hhmm.split(":").map(n => parseInt(n, 10))
    if (Number.isNaN(h)) return hhmm
    const period = h >= 12 ? "PM" : "AM"
    const hr12 = ((h + 11) % 12) + 1
    return `${hr12}:${String(m).padStart(2, "0")} ${period}`
  }
}
