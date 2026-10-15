import { Controller } from "@hotwired/stimulus"

// The order page's refund choices (manage/ticket_orders/show): as the
// manager ticks tickets or flips Keep the fees, ask the server what the
// refund comes to (ticket_orders#refund_quote, the review page's own quote)
// and show it under the choices.
export default class extends Controller {
    static targets = ["line"]
    static values = { url: String }

    async update() {
        if (!this.hasLineTarget) return
        const params = new URLSearchParams(new FormData(this.element))
        params.delete("authenticity_token")
        const request = ++this.requests
        try {
            const response = await fetch(`${this.urlValue}?${params}`, { headers: { Accept: "application/json" } })
            if (!response.ok || request !== this.requests) return
            const data = await response.json()
            this.lineTarget.textContent = data.text
        } catch (_e) {
            // Offline: the review page still shows the amount.
        }
    }

    connect() {
        this.requests = 0
    }
}
