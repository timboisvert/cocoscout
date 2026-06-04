import { Controller } from "@hotwired/stimulus"

// Distance filter as a 4-stop range slider. Each step corresponds to
// an entry in `stopsValue` (e.g. [null, 5, 10, 25]). On `input` we
// just update the readout (visual preview while dragging); on `change`
// (release) we navigate to the new URL.
export default class extends Controller {
  static targets = ["slider", "readout"]
  static values  = {
    stops:   Array,
    baseUrl: String,
    baseQp:  Object
  }

  preview() {
    const idx = parseInt(this.sliderTarget.value, 10)
    this.readoutTarget.textContent = this.labelFor(idx)
  }

  commit() {
    const idx   = parseInt(this.sliderTarget.value, 10)
    const miles = this.stopsValue[idx]
    const qp    = { ...this.baseQpValue }
    if (miles == null || miles === "" || miles === false) {
      delete qp.within
    } else {
      qp.within = miles
    }
    window.location.href = this.buildUrl(qp)
  }

  labelFor(idx) {
    const miles = this.stopsValue[idx]
    if (miles == null) return "Any"
    return `${miles} mi`
  }

  buildUrl(qp) {
    const parts = Object.entries(qp)
      .filter(([, v]) => v !== null && v !== undefined && v !== "")
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    return parts.length
      ? `${this.baseUrlValue}?${parts.join("&")}`
      : this.baseUrlValue
  }
}
