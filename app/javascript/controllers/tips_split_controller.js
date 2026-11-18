import { Controller } from "@hotwired/stimulus"

// The tips modal works the split out again while it stays open (Tim,
// 2026-11-13): add someone, or take someone off, and the shares change in
// front of you. Nothing is saved until Save the split. The server runs the
// same changes Save would, rolls them back, and sends the modal back; its
// panel replaces this one's, so the modal itself (and its open state) stays.
export default class extends Controller {
  static targets = ["panel"]
  static values = { url: String }

  add() {
    const select = this.form?.querySelector('[name="new_share[person_id]"]')
    if (!select?.value) {
      select?.focus()
      return
    }
    this.preview()
  }

  remove(event) {
    const personId = event.currentTarget.dataset.personId
    if (!personId || !this.form) return

    const input = document.createElement("input")
    input.type = "hidden"
    input.name = `shares[${personId}][remove]`
    input.value = "1"
    this.form.appendChild(input)
    this.preview()
  }

  get form() {
    return this.panelTarget.querySelector("form")
  }

  async preview() {
    if (this.busy) return
    this.busy = true

    const data = new FormData(this.form)
    data.delete("_method")
    data.set("modal_id", this.element.id)
    const scroller = this.panelTarget.querySelector("[data-tips-split-scroll]")
    const top = scroller ? scroller.scrollTop : 0
    this.panelTarget.setAttribute("aria-busy", "true")
    this.panelTarget.classList.add("pointer-events-none")
    scroller?.classList.add("opacity-60")

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        body: data,
        credentials: "same-origin",
        headers: {
          Accept: "text/html",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        }
      })
      if (!response.ok) throw new Error(`Preview failed: ${response.status}`)

      const doc = new DOMParser().parseFromString(await response.text(), "text/html")
      const fresh = doc.getElementById(this.element.id)?.querySelector('[data-tips-split-target="panel"]')
      if (!fresh) throw new Error("Preview came back without the modal")

      this.panelTarget.innerHTML = fresh.innerHTML
      const next = this.panelTarget.querySelector("[data-tips-split-scroll]")
      if (next) next.scrollTop = top
    } catch (error) {
      console.error(error)
      scroller?.classList.remove("opacity-60")
      this.showError()
    } finally {
      this.panelTarget.removeAttribute("aria-busy")
      this.panelTarget.classList.remove("pointer-events-none")
      this.busy = false
    }
  }

  showError() {
    const place = this.panelTarget.querySelector("[data-tips-split-error]")
    if (place) place.classList.remove("hidden")
  }
}
