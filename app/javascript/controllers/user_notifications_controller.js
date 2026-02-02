import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

const consumer = createConsumer()

// Handles real-time user notifications:
// - Unread message count updates
// - New message toasts
export default class extends Controller {
    static targets = ["unreadBadge", "toastContainer"]
    static values = {
        userId: Number
    }

    connect() {
        // Try to connect to ActionCable, but don't break if it fails
        try {
            this.subscription = consumer.subscriptions.create(
                { channel: "UserNotificationsChannel" },
                {
                    connected: () => this.handleConnected(),
                    disconnected: () => this.handleDisconnected(),
                    received: (data) => this.handleReceived(data)
                }
            )
        } catch (error) {
            console.warn("Could not connect to UserNotificationsChannel:", error)
        }
    }

    disconnect() {
        if (this.subscription) {
            try {
                this.subscription.unsubscribe()
            } catch (error) {
                console.warn("Error unsubscribing:", error)
            }
        }
    }

    handleConnected() {
        // Connection established
    }

    handleDisconnected() {
        // Connection closed
    }

    handleReceived(data) {
        switch (data.type) {
            case "unread_count":
                this.updateUnreadBadge(data.count)
                break
            case "new_message":
                this.showNewMessageToast(data)
                break
        }
    }

    updateUnreadBadge(count) {
        // Update all unread badges on the page
        const badges = document.querySelectorAll("[data-unread-badge]")
        badges.forEach(badge => {
            if (count > 0) {
                badge.textContent = count > 99 ? "99+" : count
                badge.classList.remove("hidden")
            } else {
                badge.classList.add("hidden")
            }
        })
    }

    showNewMessageToast(data) {
        // Create a toast notification
        const toast = document.createElement("div")
        toast.className = "fixed bottom-4 right-4 bg-white rounded-lg shadow-lg border border-gray-200 p-4 max-w-sm z-50 transform translate-y-0 transition-all duration-300"
        toast.innerHTML = `
            <div class="flex items-start gap-3">
                <div class="flex-shrink-0">
                    <svg class="w-6 h-6 text-pink-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                    </svg>
                </div>
                <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-gray-900">${data.sender_name}</p>
                    <p class="text-sm text-gray-500 truncate">${data.subject || "New message"}</p>
                </div>
                <button type="button" class="flex-shrink-0 text-gray-400 hover:text-gray-600" data-action="click->user-notifications#dismissToast">
                    <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                </button>
            </div>
            ${data.message_url ? `<a href="${data.message_url}" class="mt-2 block text-sm text-pink-600 hover:text-pink-500">View message →</a>` : ''}
        `

        document.body.appendChild(toast)

        // Auto-dismiss after 5 seconds
        setTimeout(() => {
            toast.classList.add("translate-y-4", "opacity-0")
            setTimeout(() => toast.remove(), 300)
        }, 5000)
    }

    dismissToast(event) {
        const toast = event.target.closest("[class*='fixed bottom']")
        if (toast) {
            toast.classList.add("translate-y-4", "opacity-0")
            setTimeout(() => toast.remove(), 300)
        }
    }
}
