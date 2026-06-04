import { Controller } from "@hotwired/stimulus"

// Find-or-add venue picker.
//
// Drops in on top of a venue name input. As the user types, we hit the
// lookup endpoint, show top matches, and let them either pick one
// (which auto-fills the address fields + a hidden venue_id) or
// continue typing to create a new one.
//
// Targets:
//   nameInput       — the visible name input (the trigger)
//   results         — container where we render match cards
//   addressFields   — wrapping div containing the rest of the address inputs
//   address1, neighborhood, city, state, postalCode — those address inputs
//   selectedBanner  — small "Using existing venue: …" banner that shows
//                     after a pick, with a "use a different one" link
//   venueIdInput    — hidden input that carries the selected venue's id
//
// Values:
//   url             — the JSON lookup endpoint
//   minLength       — how many chars before we hit the API (default 2)
export default class extends Controller {
  static targets = [
    "nameInput", "results", "addressFields",
    "address1", "neighborhood", "city", "state", "postalCode",
    "selectedBanner", "venueIdInput"
  ]
  static values = {
    url:       String,
    minLength: { type: Number, default: 2 }
  }

  connect() {
    this._timer = null
    this._lastQuery = ""
    this._fetchAbort = null
    this.refresh()
  }

  search() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.fetchOnce(), 220)
  }

  async fetchOnce() {
    const q = this.nameInputTarget.value.trim()
    if (q === this._lastQuery) return
    this._lastQuery = q

    if (q.length < this.minLengthValue) {
      this.renderEmpty()
      return
    }

    // Cancel any in-flight request — keeps the UI responsive while
    // typing fast.
    if (this._fetchAbort) this._fetchAbort.abort()
    this._fetchAbort = new AbortController()

    try {
      const url = `${this.urlValue}?q=${encodeURIComponent(q)}`
      const res = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: this._fetchAbort.signal
      })
      const data = await res.json()
      this.render(data.results || [])
    } catch (e) {
      if (e.name !== "AbortError") {
        this.renderEmpty()
      }
    }
  }

  render(results) {
    if (!this.hasResultsTarget) return
    if (results.length === 0) {
      this.resultsTarget.innerHTML = `
        <div class="text-xs text-gray-500 italic px-2 py-1">
          No existing venue matches — keep typing to add a new one below.
        </div>
      `
      return
    }
    const cards = results.map((v) => {
      const addr = [v.address1, v.city, v.state].filter(Boolean).join(", ")
      const meta = [
        addr,
        v.neighborhood ? `Neighborhood: ${v.neighborhood}` : null,
        `${v.mic_count} mic${v.mic_count === 1 ? "" : "s"} here`
      ].filter(Boolean).join(" · ")
      return `
        <button type="button"
                data-action="click->venue-finder#selectExisting"
                data-venue-id="${v.id}"
                data-venue-name="${this.escape(v.name)}"
                data-venue-address1="${this.escape(v.address1 || "")}"
                data-venue-neighborhood="${this.escape(v.neighborhood || "")}"
                data-venue-city="${this.escape(v.city || "")}"
                data-venue-state="${this.escape(v.state || "")}"
                data-venue-postal="${this.escape(v.postal_code || "")}"
                class="cursor-pointer block w-full text-left px-3 py-2 bg-white border border-gray-200 hover:border-pink-400 hover:bg-pink-50 rounded transition-colors">
          <div class="font-bold text-sm text-gray-900">${this.escape(v.name)}</div>
          <div class="text-xs text-gray-500 mt-0.5">${this.escape(meta)}</div>
        </button>
      `
    }).join("")
    this.resultsTarget.innerHTML = `
      <div class="text-[10px] uppercase tracking-wider text-gray-500 font-bold mb-1.5">Matching venues — pick one to reuse</div>
      <div class="space-y-1.5">${cards}</div>
      <div class="text-xs text-gray-500 mt-2">
        None of these? Keep typing — we'll create a new venue from the fields below.
      </div>
    `
  }

  renderEmpty() {
    if (this.hasResultsTarget) this.resultsTarget.innerHTML = ""
  }

  selectExisting(event) {
    const el = event.currentTarget
    this.nameInputTarget.value = el.dataset.venueName
    // Two name conventions are in use across the app — the submission
    // form posts `venue[field]` (nested params), the move-venue form
    // posts `venue_field` (flat). Set both; whichever matches an
    // actual input in the DOM gets populated.
    const map = {
      address1:     el.dataset.venueAddress1,
      neighborhood: el.dataset.venueNeighborhood,
      city:         el.dataset.venueCity,
      state:        el.dataset.venueState,
      postal_code:  el.dataset.venuePostal
    }
    Object.entries(map).forEach(([k, v]) => {
      this.setByName(`venue[${k}]`, v)
      this.setByName(`venue_${k}`, v)
    })
    if (this.hasVenueIdInputTarget) this.venueIdInputTarget.value = el.dataset.venueId
    this.markSelected(el.dataset.venueName)
  }

  setByName(name, value) {
    const input = this.element.querySelector(`[name="${name}"]`)
    if (input) input.value = value ?? ""
  }

  // After picking a match, collapse the result list, hide the address
  // fields (we don't want the user re-typing what we just filled), and
  // show a small "you picked X · undo" banner.
  markSelected(name) {
    if (this.hasResultsTarget) this.resultsTarget.innerHTML = ""
    if (this.hasAddressFieldsTarget) this.addressFieldsTarget.classList.add("hidden")
    if (this.hasSelectedBannerTarget) {
      this.selectedBannerTarget.classList.remove("hidden")
      const nameEl = this.selectedBannerTarget.querySelector("[data-venue-finder-target='selectedName']")
      if (nameEl) nameEl.textContent = name
    }
  }

  // "Use a different venue" link in the picked-banner — reset the
  // hidden id, re-show address inputs, focus the name input.
  resetSelection(event) {
    event?.preventDefault?.()
    if (this.hasVenueIdInputTarget) this.venueIdInputTarget.value = ""
    if (this.hasSelectedBannerTarget) this.selectedBannerTarget.classList.add("hidden")
    if (this.hasAddressFieldsTarget) this.addressFieldsTarget.classList.remove("hidden")
    if (this.hasNameInputTarget) {
      this.nameInputTarget.focus()
      this.nameInputTarget.select()
    }
    this._lastQuery = ""
    this.fetchOnce()
  }

  refresh() {
    // Initial state — when a venue_id is already populated (e.g. after
    // a validation re-render), reflect that as "selected" so we don't
    // immediately dupe.
    if (this.hasVenueIdInputTarget && this.venueIdInputTarget.value) {
      this.markSelected(this.nameInputTarget.value)
    }
  }

  escape(s) {
    const d = document.createElement("div")
    d.textContent = s ?? ""
    return d.innerHTML.replace(/"/g, "&quot;")
  }
}
