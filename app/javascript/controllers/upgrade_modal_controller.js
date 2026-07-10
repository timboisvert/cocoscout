import { Controller } from "@hotwired/stimulus"

// Opens a Pro upgrade modal when a locked feature is clicked. The rich,
// feature-specific content is fetched on demand from
// /manage/billing/upgrade/:feature so pages stay light.
//
// Trigger any element with:
//   data-action="upgrade-modal#open" data-upgrade-feature="money"
// Graceful degradation: if JS is off or the fetch fails, the element's normal
// href (the feature page) still works and the server renders a full-page paywall.
export default class extends Controller {
  static targets = ["overlay", "content"]

  connect() {
    this.keyHandler = this.handleKeydown.bind(this)
  }

  disconnect() {
    document.removeEventListener("keydown", this.keyHandler)
  }

  async open(event) {
    const trigger = event.currentTarget
    const feature = trigger.dataset.upgradeFeature
    if (!feature) return
    if (!this.hasOverlayTarget || !this.hasContentTarget) return

    // We're handling it — stop the link from navigating.
    event.preventDefault()

    this.show()
    this.contentTarget.innerHTML = this.loadingMarkup()

    try {
      const response = await fetch(`/manage/billing/upgrade/${encodeURIComponent(feature)}`, {
        headers: { "Accept": "text/html", "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin",
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      this.contentTarget.innerHTML = await response.text()
    } catch (e) {
      // Fall back to a normal navigation to the feature page (full-page paywall).
      const href = trigger.getAttribute("href")
      if (href) {
        window.location.href = href
      } else {
        this.close()
      }
    }
  }

  show() {
    this.overlayTarget.classList.remove("hidden")
    this.overlayTarget.classList.add("flex")
    document.body.style.overflow = "hidden"
    document.addEventListener("keydown", this.keyHandler)
  }

  close(event) {
    if (event) event.preventDefault()
    this.overlayTarget.classList.add("hidden")
    this.overlayTarget.classList.remove("flex")
    document.body.style.overflow = ""
    document.removeEventListener("keydown", this.keyHandler)
  }

  handleKeydown(event) {
    if (event.key === "Escape") this.close()
  }

  loadingMarkup() {
    return `<div class="py-16 text-center text-gray-400 text-sm">Loading…</div>`
  }
}
