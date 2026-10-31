import { Controller } from "@hotwired/stimulus"

// Draws a seat chart as SVG from a JSON payload (Ticketing::Seating#payload
// or Ticketing::ChartPayload) and lets people pick seats. The same picture
// for the editor (every seat pickable), the manager's seat map of a date,
// and a buyer's picker (only free seats of a type for sale). Picking fires
// "seat-map:change" with the picked seats; a form can mirror them into
// hidden inputs (inputsTarget) and a line of text (summaryTarget).
//
// data-seat-map-mode-value: "edit" (any seat), "manage" (any seat but
// killed), "buy" (free seats only, and only in sections with a tier).
// data-seat-map-max-value: how many seats may be picked (buy mode).
export default class extends Controller {
  static targets = ["svg", "inputs", "summary", "count", "total", "moveFrom", "moveTo", "moveWords"]
  static values = { payload: Object, mode: { type: String, default: "manage" }, max: { type: Number, default: 0 }, name: { type: String, default: "seat_ids[]" } }

  connect() {
    this.picked = new Map()
    this.draw()
  }

  draw() {
    const p = this.payloadValue
    const svg = this.svgTarget
    svg.setAttribute("viewBox", `0 0 ${p.width} ${p.height}`)
    svg.innerHTML = ""
    const ns = "http://www.w3.org/2000/svg"
    const make = (tag, attrs, parent = svg) => {
      const el = document.createElementNS(ns, tag)
      for (const [k, v] of Object.entries(attrs)) if (v != null) el.setAttribute(k, v)
      parent.appendChild(el)
      return el
    }
    // The stage, so the picture reads the right way up.
    make("rect", { x: p.width * 0.3, y: 6, width: p.width * 0.4, height: 14, rx: 4, class: "fill-gray-300" })
    make("text", { x: p.width / 2, y: 17, "text-anchor": "middle", class: "fill-gray-600 text-[9px] uppercase tracking-wide" }).textContent = "Stage"
    for (const section of p.sections) {
      const g = make("g", { "data-section-id": section.id })
      make("text", { x: section.x, y: section.y + 10, class: "fill-gray-500 text-[11px] font-semibold" }, g).textContent =
        section.tier_name ? `${section.name} · ${section.tier_name}${section.price_cents != null ? " · $" + (section.price_cents / 100).toFixed(2) : ""}` : section.name
      if (section.kind === "standing") {
        const r = make("rect", { x: section.x, y: section.y + 16, width: section.width, height: section.height - 16, rx: 8,
          class: `fill-pink-50 stroke-pink-300 ${this.modeValue === "buy" && section.tier_id ? "cursor-pointer" : ""}` }, g)
        make("text", { x: section.x + section.width / 2, y: section.y + section.height / 2 + 12, "text-anchor": "middle", class: "fill-gray-700 text-[12px]" }, g).textContent =
          section.standing_remaining != null ? `Standing · ${section.standing_remaining} of ${section.standing_capacity} left` : `Standing room for ${section.standing_capacity}`
        r.dataset.standing = section.id
        continue
      }
      if (section.kind === "tables") {
        // The table top under each ring of seats, named.
        const tables = new Map()
        for (const seat of section.seats) (tables.get(seat.row) || tables.set(seat.row, []).get(seat.row)).push(seat)
        for (const [row, seats] of tables) {
          const cx = seats.reduce((s, x) => s + x.x, 0) / seats.length, cy = seats.reduce((s, x) => s + x.y, 0) / seats.length
          make("circle", { cx, cy, r: 26, class: "fill-gray-100 stroke-gray-300" }, g)
          make("text", { x: cx, y: cy + 4, "text-anchor": "middle", class: "fill-gray-500 text-[10px] font-semibold pointer-events-none" }, g).textContent = row
        }
      }
      for (const seat of section.seats) {
        const c = make("circle", { cx: seat.x, cy: seat.y, r: 11, "data-seat-id": seat.id, "data-status": seat.status, "data-kind": seat.kind, class: this.seatClass(seat, section) }, g)
        const title = make("title", {}, c)
        title.textContent = this.seatTitle(seat, section)
        if (seat.kind === "wheelchair") make("text", { x: seat.x, y: seat.y + 3.5, "text-anchor": "middle", class: "fill-current text-[9px] pointer-events-none" }, g).textContent = "W"
        if (seat.kind === "companion") make("text", { x: seat.x, y: seat.y + 3.5, "text-anchor": "middle", class: "fill-current text-[9px] pointer-events-none" }, g).textContent = "C"
        if (seat.kind === "restricted_view") make("text", { x: seat.x, y: seat.y + 3.5, "text-anchor": "middle", class: "fill-current text-[9px] pointer-events-none" }, g).textContent = "R"
        if (this.pickable(seat, section)) {
          c.classList.add("cursor-pointer")
          c.addEventListener("click", () => this.toggle(seat, section, c))
        }
      }
    }
  }

  seatClass(seat, section) {
    if (this.picked.has(seat.id)) return "fill-pink-600 stroke-pink-700 text-white"
    switch (seat.status) {
      case "killed": return "fill-gray-100 stroke-gray-200 text-gray-300"
      case "sold": return "fill-gray-400 stroke-gray-500 text-white"
      case "mine": return "fill-green-500 stroke-green-600 text-white"
      case "held": return "fill-amber-200 stroke-amber-400 text-amber-900"
      default:
        if (this.modeValue === "buy" && !section.tier_id) return "fill-gray-200 stroke-gray-300 text-gray-400"
        if (seat.kind === "wheelchair" || seat.kind === "companion") return "fill-sky-100 stroke-sky-400 text-sky-800"
        if (seat.kind === "restricted_view") return "fill-white stroke-gray-400 text-gray-500"
        return "fill-white stroke-gray-400 text-gray-700"
    }
  }

  seatTitle(seat, section) {
    const bits = [`${section.name} ${seat.label}`]
    if (seat.kind !== "standard") bits.push(seat.kind.replace("_", " "))
    if (seat.status === "sold") bits.push("sold")
    if (seat.status === "held") bits.push(`held: ${seat.hold?.name || ""}`)
    if (seat.status === "killed") bits.push("not for sale")
    if (seat.note) bits.push(seat.note)
    return bits.join(" · ")
  }

  pickable(seat, section) {
    if (this.modeValue === "edit") return true
    if (seat.status === "killed") return false
    if (this.modeValue === "buy") return seat.status === "free" && !!section.tier_id
    return true
  }

  toggle(seat, section, circle) {
    if (this.picked.has(seat.id)) {
      this.picked.delete(seat.id)
    } else {
      if (this.maxValue > 0 && this.picked.size >= this.maxValue) {
        if (this.maxValue === 1) this.picked.clear(); else return this.flash(`Up to ${this.maxValue} seats.`)
      }
      this.picked.set(seat.id, { seat, section })
    }
    this.draw()
    this.sync()
  }

  clear() {
    this.picked.clear()
    this.draw()
    this.sync()
  }

  sync() {
    const list = [...this.picked.values()]
    if (this.hasInputsTarget) {
      this.inputsTarget.innerHTML = list.map(({ seat }) => `<input type="hidden" name="${this.nameValue}" value="${seat.id}">`).join("")
    }
    if (this.hasSummaryTarget) {
      this.summaryTarget.textContent = list.length ? list.map(({ seat, section }) => `${section.name} ${seat.label}`).join(", ") : ""
    }
    if (this.hasCountTarget) this.countTarget.textContent = list.length
    if (this.hasTotalTarget) {
      const cents = list.reduce((sum, { section }) => sum + (section.price_cents || 0), 0)
      this.totalTarget.textContent = list.length ? `$${(cents / 100).toFixed(2)}` : ""
    }
    // Moving a ticket: one sold seat and one free seat picked together.
    if (this.hasMoveFromTarget) {
      const sold = list.find(({ seat }) => seat.status === "sold")
      const free = list.find(({ seat }) => seat.status === "free")
      this.moveFromTarget.value = sold ? sold.seat.ticket_id : ""
      this.moveToTarget.value = free ? free.seat.id : ""
      if (this.hasMoveWordsTarget) {
        this.moveWordsTarget.textContent = sold && free ? `${sold.section.name} ${sold.seat.label} → ${free.section.name} ${free.seat.label}`
          : sold ? "Now tap the free seat to move them to." : "Tap a sold seat, then a free one."
      }
    }
    this.dispatch("change", { detail: { seats: list.map(({ seat, section }) => ({ id: seat.id, label: seat.label, section_id: section.id, tier_id: section.tier_id })) } })
  }

  flash(message) {
    if (this.hasSummaryTarget) this.summaryTarget.textContent = message
  }
}
