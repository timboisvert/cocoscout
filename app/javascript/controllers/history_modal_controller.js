import { Controller } from "@hotwired/stimulus"

// Opens a person-history modal and infinite-scrolls through the entries.
export default class extends Controller {
  static targets = ["modal", "list", "scroller", "loading", "empty", "end"]
  static values = { url: String, modalId: String }

  connect() {
    this.nextBefore = null
    this.loading = false
    this.exhausted = false
  }

  open(event) {
    if (event) event.preventDefault()
    this.modalTarget.classList.remove("hidden")
    if (this.listTarget.childElementCount === 0) {
      this.loadMore()
    }
  }

  close(event) {
    if (event) event.preventDefault()
    this.modalTarget.classList.add("hidden")
  }

  backdropClose(event) {
    // Only close if the click landed on the modal backdrop itself, not inner content
    if (event.target === this.modalTarget) {
      this.close(event)
    }
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  onScroll() {
    if (this.exhausted || this.loading) return
    const el = this.scrollerTarget
    const remaining = el.scrollHeight - el.scrollTop - el.clientHeight
    if (remaining < 200) this.loadMore()
  }

  async loadMore() {
    if (this.exhausted || this.loading) return
    this.loading = true
    this.loadingTarget.classList.remove("hidden")

    const url = new URL(this.urlValue, window.location.origin)
    if (this.nextBefore) url.searchParams.set("before", this.nextBefore)

    try {
      const res = await fetch(url.toString(), {
        headers: { "Accept": "application/json" }
      })
      const data = await res.json()

      if (data.html && data.html.trim().length > 0) {
        this.listTarget.insertAdjacentHTML("beforeend", data.html)
      } else if (this.listTarget.childElementCount === 0) {
        this.emptyTarget.classList.remove("hidden")
      }

      this.nextBefore = data.next_before
      if (!data.has_more || !data.next_before) {
        this.exhausted = true
        if (this.listTarget.childElementCount > 0) {
          this.endTarget.classList.remove("hidden")
        }
      }
    } catch (e) {
      console.error("Failed to load history:", e)
    } finally {
      this.loading = false
      this.loadingTarget.classList.add("hidden")
    }
  }
}
