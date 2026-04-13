import { Controller } from "@hotwired/stimulus"

// Handles refresh button with spinning icon + auto-refresh on stale data
// Usage:
//   <div data-controller="refresh-financials"
//        data-refresh-financials-url-value="/manage/money/refresh"
//        data-refresh-financials-cached-at-value="2026-04-13T12:00:00Z"
//        data-refresh-financials-stale-minutes-value="15">
//     <button data-action="click->refresh-financials#refresh"
//             data-refresh-financials-target="button">
//       <svg data-refresh-financials-target="icon">...</svg>
//     </button>
//   </div>
export default class extends Controller {
    static targets = ["icon", "button"]
    static values = {
        url: String,
        cachedAt: String,
        staleMinutes: { type: Number, default: 15 }
    }

    connect() {
        if (this.cachedAtValue) {
            const cachedAt = new Date(this.cachedAtValue)
            const minutesAgo = (Date.now() - cachedAt.getTime()) / 60000
            if (minutesAgo >= this.staleMinutesValue) {
                this.refresh()
            }
        }
    }

    async refresh() {
        if (this.refreshing) return
        this.refreshing = true

        // Start spinning
        if (this.hasIconTarget) {
            this.iconTarget.classList.add("animate-spin")
        }
        if (this.hasButtonTarget) {
            this.buttonTarget.disabled = true
            this.buttonTarget.classList.add("opacity-50", "cursor-not-allowed")
        }

        try {
            const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
            const response = await fetch(this.urlValue, {
                method: "POST",
                headers: {
                    "X-CSRF-Token": csrfToken,
                    "Accept": "application/json"
                }
            })

            if (response.ok) {
                // Reload current page via Turbo to show fresh data
                Turbo.visit(window.location.href, { action: "replace" })
            }
        } catch (e) {
            // Stop spinning on error and re-enable
            if (this.hasIconTarget) {
                this.iconTarget.classList.remove("animate-spin")
            }
            if (this.hasButtonTarget) {
                this.buttonTarget.disabled = false
                this.buttonTarget.classList.remove("opacity-50", "cursor-not-allowed")
            }
            this.refreshing = false
        }
    }
}
