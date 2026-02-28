import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

const consumer = createConsumer()

// Handles real-time ticketing engine updates:
// - Engine status changes (syncing, active, paused)
// - Per-show sync progress
// - Sales updates
// - Activity feed
export default class extends Controller {
    static targets = [
        "engineStatus",
        "syncButton",
        "syncStatus",
        "showRow",
        "activityFeed",
        "activityList"
    ]

    static values = {
        productionId: Number
    }

    connect() {
        if (!this.productionIdValue) {
            console.warn("TicketingDashboard: No production ID provided")
            return
        }

        try {
            this.subscription = consumer.subscriptions.create(
                { channel: "TicketingChannel", production_id: this.productionIdValue },
                {
                    connected: () => this.handleConnected(),
                    disconnected: () => this.handleDisconnected(),
                    received: (data) => this.handleReceived(data)
                }
            )
        } catch (error) {
            console.warn("Could not connect to TicketingChannel:", error)
        }
    }

    disconnect() {
        if (this.subscription) {
            try {
                this.subscription.unsubscribe()
            } catch (error) {
                console.warn("Error unsubscribing from TicketingChannel:", error)
            }
        }
    }

    handleConnected() {
        // Mark as connected - could show indicator
        this.element.dataset.cableConnected = "true"
    }

    handleDisconnected() {
        this.element.dataset.cableConnected = "false"
    }

    handleReceived(data) {
        switch (data.type) {
            case "engine_status":
                this.updateEngineStatus(data)
                break
            case "show_sync":
                this.updateShowSync(data)
                break
            case "sales_update":
                this.updateSales(data)
                break
            case "activity":
                this.addActivity(data)
                break
        }
    }

    // ============================================
    // Actions (called from buttons)
    // ============================================

    syncNow() {
        if (this.subscription) {
            // Update button to show syncing state
            if (this.hasSyncButtonTarget) {
                this.syncButtonTarget.disabled = true
                this.syncButtonTarget.innerHTML = `
          <svg class="animate-spin h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          Syncing...
        `
            }

            // Request sync via ActionCable
            this.subscription.perform("request_sync")
        }
    }

    // ============================================
    // Update handlers
    // ============================================

    updateEngineStatus(data) {
        if (this.hasEngineStatusTarget) {
            const badge = this.engineStatusTarget

            // Update badge text and color
            badge.textContent = this.formatStatus(data.status)
            badge.className = this.statusBadgeClasses(data.status)

            // Add pulse animation for syncing
            if (data.status === "syncing") {
                badge.classList.add("animate-pulse")
            } else {
                badge.classList.remove("animate-pulse")
            }
        }

        // Update sync status message
        if (this.hasSyncStatusTarget && data.message) {
            this.syncStatusTarget.textContent = data.message
        }

        // Reset sync button when sync completes
        if (data.status !== "syncing" && this.hasSyncButtonTarget) {
            this.resetSyncButton()
        }
    }

    updateShowSync(data) {
        const showRow = this.findShowRow(data.show_id)
        if (!showRow) return

        // Find status indicator in the row
        const statusIndicator = showRow.querySelector("[data-status-indicator]")
        if (statusIndicator) {
            statusIndicator.className = this.showStatusClasses(data.status)
            statusIndicator.dataset.status = data.status

            // Update tooltip/title
            if (data.message) {
                statusIndicator.title = data.message
            }
        }

        // Update status text
        const statusText = showRow.querySelector("[data-status-text]")
        if (statusText) {
            statusText.textContent = this.formatShowStatus(data.status)
        }

        // Highlight row briefly to show update
        this.flashRow(showRow)
    }

    updateSales(data) {
        const showRow = this.findShowRow(data.show_id)
        if (!showRow) return

        // Update sold count
        const soldCount = showRow.querySelector("[data-sold-count]")
        if (soldCount) {
            const oldValue = parseInt(soldCount.textContent) || 0
            soldCount.textContent = data.sold

            // Animate if value increased
            if (data.sold > oldValue) {
                soldCount.classList.add("text-green-600", "font-bold")
                setTimeout(() => {
                    soldCount.classList.remove("text-green-600", "font-bold")
                }, 2000)
            }
        }

        // Update available count
        const availableCount = showRow.querySelector("[data-available-count]")
        if (availableCount) {
            availableCount.textContent = data.available
        }

        // Highlight row
        this.flashRow(showRow)
    }

    addActivity(data) {
        if (!this.hasActivityListTarget) return

        // Create activity item
        const item = document.createElement("div")
        item.className = "activity-item flex items-start gap-3 p-3 bg-white border-b border-gray-100 opacity-0 transform -translate-y-2 transition-all duration-300"
        item.innerHTML = `
      <div class="flex-shrink-0">
        ${this.activityIcon(data.event_type)}
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm text-gray-900">${this.escapeHtml(data.message)}</p>
        <p class="text-xs text-gray-500">Just now</p>
      </div>
    `

        // Prepend to list
        this.activityListTarget.prepend(item)

        // Trigger animation
        requestAnimationFrame(() => {
            item.classList.remove("opacity-0", "-translate-y-2")
        })

        // Remove old items if too many (keep last 20)
        const items = this.activityListTarget.querySelectorAll(".activity-item")
        if (items.length > 20) {
            items[items.length - 1].remove()
        }
    }

    // ============================================
    // Helpers
    // ============================================

    findShowRow(showId) {
        return this.showRowTargets.find(row => row.dataset.showId === String(showId))
    }

    flashRow(row) {
        row.classList.add("bg-yellow-50")
        setTimeout(() => {
            row.classList.remove("bg-yellow-50")
            row.classList.add("transition-colors", "duration-500")
        }, 100)
        setTimeout(() => {
            row.classList.remove("transition-colors", "duration-500")
        }, 600)
    }

    resetSyncButton() {
        if (this.hasSyncButtonTarget) {
            this.syncButtonTarget.disabled = false
            this.syncButtonTarget.innerHTML = `
        <svg class="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
        </svg>
        Sync Now
      `
        }
    }

    formatStatus(status) {
        const labels = {
            active: "Active",
            syncing: "Syncing",
            paused: "Paused",
            draft: "Draft",
            error: "Error"
        }
        return labels[status] || status
    }

    formatShowStatus(status) {
        const labels = {
            pending: "Pending",
            syncing: "Syncing...",
            listed: "Listed",
            error: "Error"
        }
        return labels[status] || status
    }

    statusBadgeClasses(status) {
        const baseClasses = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
        const colorClasses = {
            active: "bg-green-100 text-green-800",
            syncing: "bg-blue-100 text-blue-800",
            paused: "bg-yellow-100 text-yellow-800",
            draft: "bg-gray-100 text-gray-800",
            error: "bg-red-100 text-red-800"
        }
        return `${baseClasses} ${colorClasses[status] || colorClasses.draft}`
    }

    showStatusClasses(status) {
        const baseClasses = "w-3 h-3 rounded-full"
        const colorClasses = {
            pending: "bg-gray-300",
            syncing: "bg-blue-400 animate-pulse",
            listed: "bg-green-500",
            error: "bg-red-500"
        }
        return `${baseClasses} ${colorClasses[status] || colorClasses.pending}`
    }

    activityIcon(eventType) {
        const icons = {
            sync_started: `<div class="w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center"><svg class="w-4 h-4 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" /></svg></div>`,
            sync_complete: `<div class="w-8 h-8 rounded-full bg-green-100 flex items-center justify-center"><svg class="w-4 h-4 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" /></svg></div>`,
            listing_created: `<div class="w-8 h-8 rounded-full bg-purple-100 flex items-center justify-center"><svg class="w-4 h-4 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" /></svg></div>`,
            sales_received: `<div class="w-8 h-8 rounded-full bg-pink-100 flex items-center justify-center"><svg class="w-4 h-4 text-pink-600" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg></div>`,
            error: `<div class="w-8 h-8 rounded-full bg-red-100 flex items-center justify-center"><svg class="w-4 h-4 text-red-600" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg></div>`
        }
        return icons[eventType] || icons.sync_started
    }

    escapeHtml(text) {
        const div = document.createElement("div")
        div.textContent = text
        return div.innerHTML
    }
}
