import { Controller } from "@hotwired/stimulus"

// Displays a countdown for "Opens in X" with live mm:ss when under 15 minutes
// Refreshes the page when the countdown reaches zero
export default class extends Controller {
    static values = {
        opensAt: String  // ISO 8601 datetime string
    }

    connect() {
        this.update()
        this.interval = setInterval(() => this.update(), 1000)
    }

    disconnect() {
        if (this.interval) {
            clearInterval(this.interval)
        }
    }

    update() {
        const opensAt = new Date(this.opensAtValue)
        const now = new Date()
        const diffMs = opensAt - now

        if (diffMs <= 0) {
            this.element.textContent = "Opening now..."
            if (this.interval) {
                clearInterval(this.interval)
            }
            // Small delay to show "Opening now..." before refresh
            setTimeout(() => {
                window.location.reload()
            }, 1500)
            return
        }

        const totalSeconds = Math.floor(diffMs / 1000)
        const totalMinutes = Math.floor(totalSeconds / 60)
        const seconds = totalSeconds % 60
        const hours = Math.floor(totalMinutes / 60)
        const minutes = totalMinutes % 60

        if (totalMinutes >= 60) {
            // More than an hour - show hours
            const displayHours = Math.ceil(totalMinutes / 60)
            this.element.textContent = `Opens in ${displayHours} hour${displayHours === 1 ? '' : 's'}`
        } else if (totalMinutes >= 15) {
            // 15-60 minutes - show just minutes
            this.element.textContent = `Opens in ${totalMinutes} minutes`
        } else {
            // Under 15 minutes - show mm:ss countdown
            const paddedSeconds = seconds.toString().padStart(2, '0')
            this.element.textContent = `Opens in ${totalMinutes}:${paddedSeconds}`
        }
    }
}
