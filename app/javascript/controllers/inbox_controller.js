import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Handles real-time inbox updates via ActionCable
// Shows a "New messages" banner when new messages arrive
export default class extends Controller {
    static targets = ["banner", "count"]

    connect() {
        this.newMessageIds = new Set()
        this.consumer = createConsumer()
        this.subscription = this.consumer.subscriptions.create("UserInboxChannel", {
            received: this.handleReceived.bind(this)
        })
    }

    disconnect() {
        if (this.subscription) {
            this.subscription.unsubscribe()
        }
        if (this.consumer) {
            this.consumer.disconnect()
        }
    }

    handleReceived(data) {
        if (data.type === "new_message") {
            // Track new message by root_message_id to avoid counting replies multiple times
            this.newMessageIds.add(data.root_message_id)
            this.updateBanner()
        }
    }

    updateBanner() {
        const count = this.newMessageIds.size
        if (count > 0 && this.hasBannerTarget) {
            this.countTarget.textContent = count === 1 ? "1 new message" : `${count} new messages`
            this.bannerTarget.classList.remove("hidden")
        }
    }

    refresh() {
        // Reload the page to show new messages
        window.location.reload()
    }
}
