import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["clock"]
    static values = {
        until: String,
        expiredAction: String  // Optional: "refresh" to refresh page when countdown ends
    }

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

        if (diff <= 0) {
            diff = 0
            this.clockTarget.textContent = "closed"
            clearInterval(this.timer)

            // Handle expired action
            if (this.hasExpiredActionValue && this.expiredActionValue === "refresh") {
                // Small delay before refresh to let user see "closed"
                setTimeout(() => {
                    window.location.reload()
                }, 1000)
            }
            return
        }

        this.clockTarget.textContent = this.formatCountdown(until, now, diff)
    }

    formatCountdown(until, now, diffSeconds) {
        const hours = Math.floor(diffSeconds / 3600)
        const minutes = Math.floor((diffSeconds % 3600) / 60)
        const seconds = diffSeconds % 60

        // Get start of today and tomorrow for comparison
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        const startOfTomorrow = new Date(startOfToday)
        startOfTomorrow.setDate(startOfTomorrow.getDate() + 1)
        const startOfDayAfterTomorrow = new Date(startOfTomorrow)
        startOfDayAfterTomorrow.setDate(startOfDayAfterTomorrow.getDate() + 1)

        // If closes today, show countdown: "12h 32m 45s"
        if (until < startOfTomorrow) {
            return `${hours}h ${minutes}m ${seconds}s`
        }

        // If closes tomorrow, show: "tomorrow at 6:00 AM"
        if (until < startOfDayAfterTomorrow) {
            const timeStr = until.toLocaleTimeString('en-US', {
                hour: 'numeric',
                minute: '2-digit',
                hour12: true
            })
            return `tomorrow at ${timeStr}`
        }

        // Beyond tomorrow, show: "in X days"
        const days = Math.floor(diffSeconds / 86400)
        return `in ${days} day${days === 1 ? '' : 's'}`
    }
}
