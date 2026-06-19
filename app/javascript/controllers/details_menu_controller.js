import { Controller } from "@hotwired/stimulus"

// Closes a native <details> dropdown menu on outside click or Escape.
export default class extends Controller {
    connect() {
        this._onDoc = (e) => { if (!this.element.contains(e.target)) this.element.open = false }
        this._onKey = (e) => { if (e.key === "Escape") this.element.open = false }
        document.addEventListener("click", this._onDoc)
        document.addEventListener("keydown", this._onKey)
    }

    disconnect() {
        document.removeEventListener("click", this._onDoc)
        document.removeEventListener("keydown", this._onKey)
    }
}
