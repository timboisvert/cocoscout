import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["clock"]
    static values = { until: String }

    connect() {
        this.updateClock()
        this.timer = setInterval(() => this.updateClock(), 1000)
    }

    disconnect() {
        clearInterval(this.timer)
    }

    updateClock() {
        const until = new Date(this.untilValue)
        const now = new Date()
        let diff = Math.floor((until - now) / 1000)
        if (diff < 0) diff = 0
        const hours = Math.floor(diff / 3600)
        const minutes = Math.floor((diff % 3600) / 60)
        const seconds = diff % 60
        this.clockTarget.textContent = `${hours}h ${minutes}m ${seconds}s`
    }
}
