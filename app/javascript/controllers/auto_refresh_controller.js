import { Controller } from "@hotwired/stimulus"

// Automatically refreshes the page after a specified interval
// Usage: <div data-controller="auto-refresh" data-auto-refresh-interval-value="30000">
export default class extends Controller {
    static values = {
        interval: { type: Number, default: 30000 } // 30 seconds default
    }

    connect() {
        this.timeout = setTimeout(() => {
            window.location.reload()
        }, this.intervalValue)
    }

    disconnect() {
        if (this.timeout) {
            clearTimeout(this.timeout)
        }
    }
}
