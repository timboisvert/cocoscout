import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Create consumer lazily to ensure it uses the current session
let consumer = null
function getConsumer() {
    if (!consumer) {
        consumer = createConsumer()
    }
    return consumer
}

// Force reconnect when user changes (e.g., after impersonation)
function resetConsumer() {
    if (consumer) {
        consumer.disconnect()
        consumer = null
    }
}

// Handles real-time updates for a message thread:
// - New replies appearing live
// - Typing indicators
// - Online presence
// - Comment form visibility
export default class extends Controller {
    static targets = ["replies", "typingIndicator", "presenceCount", "commentForm", "commentBody"]
    static values = {
        messageId: Number,
        currentUserId: Number
    }

    connect() {
        this.typingUsers = new Map()
        this.presentUsers = new Set()
        this.typingTimeout = null
        this.isTyping = false

        // Check if user changed (e.g., after impersonation) and reset connection
        const lastUserId = parseInt(sessionStorage.getItem('cableUserId') || '0', 10)
        if (lastUserId && lastUserId !== this.currentUserIdValue) {
            resetConsumer()
        }
        sessionStorage.setItem('cableUserId', this.currentUserIdValue.toString())

        // Listen for typing events from nested reply-form controllers
        this.boundHandleReplyTyping = this.handleReplyTyping.bind(this)
        this.element.addEventListener("reply-form:typing", this.boundHandleReplyTyping)

        // Try to connect to ActionCable, but don't break if it fails
        try {
            this.subscription = getConsumer().subscriptions.create(
                { channel: "MessageThreadChannel", message_id: this.messageIdValue },
                {
                    connected: () => this.handleConnected(),
                    disconnected: () => this.handleDisconnected(),
                    received: (data) => this.handleReceived(data)
                }
            )
        } catch (error) {
            console.warn("Could not connect to MessageThreadChannel:", error)
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
        if (this.typingTimeout) {
            clearTimeout(this.typingTimeout)
        }
        if (this.boundHandleReplyTyping) {
            this.element.removeEventListener("reply-form:typing", this.boundHandleReplyTyping)
        }
    }

    // Handle typing events from nested reply-form controllers
    handleReplyTyping() {
        this.userTyping()
    }

    handleConnected() {
        // Connection established
    }

    handleDisconnected() {
        // Connection closed
    }

    handleReceived(data) {
        console.log("ActionCable received:", data.type, data)
        switch (data.type) {
            case "new_reply":
                this.handleNewReply(data)
                break
            case "typing":
                this.handleTyping(data)
                break
            case "stopped_typing":
                this.handleStoppedTyping(data)
                break
            case "presence":
                this.handlePresence(data)
                break
        }
    }

    handleNewReply(data) {
        // Don't insert if we already have this message (prevents duplicates from our own posts)
        if (document.querySelector(`[data-message-id="${data.message_id}"]`)) {
            return
        }

        if (data.html) {
            // Check if this is a top-level reply (parent is the root message)
            const isTopLevelReply = data.parent_id === data.root_id || data.depth === 1

            if (isTopLevelReply && this.hasRepliesTarget) {
                // Insert as a top-level reply at the end
                this.repliesTarget.insertAdjacentHTML("beforeend", data.html)
            } else {
                // Find the parent reply container for nested replies
                const parentReplyDiv = document.querySelector(`[data-message-id="${data.parent_id}"]`)

                if (parentReplyDiv) {
                    // Find existing nested replies container
                    let childContainer = parentReplyDiv.querySelector('[data-nested-replies]')
                    if (!childContainer) {
                        // Create child container if it doesn't exist
                        // It needs to be inside the ml-6 wrapper to get proper indentation
                        // Find the last child that's a div inside the parent (before closing)
                        childContainer = document.createElement('div')
                        childContainer.setAttribute('data-nested-replies', 'true')
                        childContainer.className = 'relative mt-3 space-y-3'

                        // Find the inner wrapper (ml-6 div or last structural div)
                        // The ml-6 div is the second child (after tree lines)
                        const innerWrapper = parentReplyDiv.querySelector(':scope > div:last-child')
                        if (innerWrapper) {
                            innerWrapper.appendChild(childContainer)
                        } else {
                            parentReplyDiv.appendChild(childContainer)
                        }
                    }
                    childContainer.insertAdjacentHTML("beforeend", data.html)
                } else if (this.hasRepliesTarget) {
                    // Fallback: insert at end of replies
                    this.repliesTarget.insertAdjacentHTML("beforeend", data.html)
                }
            }

            // Scroll to the new reply
            const newReply = document.querySelector(`[data-message-id="${data.message_id}"]`) ||
                (this.hasRepliesTarget && this.repliesTarget.lastElementChild)
            if (newReply) {
                newReply.scrollIntoView({ behavior: "smooth", block: "center" })
                // Add a brief highlight
                newReply.classList.add("ring-2", "ring-pink-300")
                setTimeout(() => {
                    newReply.classList.remove("ring-2", "ring-pink-300")
                }, 2000)
            }
        }

        // Clear the reply form if it was our message
        if (data.sender_id === this.currentUserIdValue) {
            // Hide the comment form
            this.hideCommentForm()

            // Also clear any inline reply forms
            const replyForms = document.querySelectorAll('[data-controller="reply-form"]')
            replyForms.forEach(form => {
                const trixEditor = form.querySelector("trix-editor")
                if (trixEditor && trixEditor.editor) {
                    trixEditor.editor.loadHTML("")
                }
            })
        }

        // Remove typing indicator for this user
        this.typingUsers.delete(data.sender_id)
        this.updateTypingIndicator()
    }

    handleTyping(data) {
        // Don't show typing indicator for current user
        if (data.user_id === this.currentUserIdValue) return

        this.typingUsers.set(data.user_id, {
            name: data.user_name,
            timestamp: data.timestamp
        })
        this.updateTypingIndicator()

        // Auto-remove after 5 seconds if no update
        setTimeout(() => {
            const user = this.typingUsers.get(data.user_id)
            if (user && user.timestamp === data.timestamp) {
                this.typingUsers.delete(data.user_id)
                this.updateTypingIndicator()
            }
        }, 5000)
    }

    handleStoppedTyping(data) {
        this.typingUsers.delete(data.user_id)
        this.updateTypingIndicator()
    }

    handlePresence(data) {
        if (data.action === "joined") {
            this.presentUsers.add(data.user_id)
        } else {
            this.presentUsers.delete(data.user_id)
        }
        this.updatePresenceCount()
    }

    updateTypingIndicator() {
        if (!this.hasTypingIndicatorTarget) return

        const typingNames = Array.from(this.typingUsers.values()).map(u => u.name)

        if (typingNames.length === 0) {
            this.typingIndicatorTarget.classList.add("hidden")
            this.typingIndicatorTarget.textContent = ""
        } else if (typingNames.length === 1) {
            this.typingIndicatorTarget.textContent = `${typingNames[0]} is typing...`
            this.typingIndicatorTarget.classList.remove("hidden")
        } else if (typingNames.length === 2) {
            this.typingIndicatorTarget.textContent = `${typingNames[0]} and ${typingNames[1]} are typing...`
            this.typingIndicatorTarget.classList.remove("hidden")
        } else {
            this.typingIndicatorTarget.textContent = `${typingNames.length} people are typing...`
            this.typingIndicatorTarget.classList.remove("hidden")
        }
    }

    updatePresenceCount() {
        if (!this.hasPresenceCountTarget) return

        const count = this.presentUsers.size
        if (count <= 1) {
            this.presenceCountTarget.classList.add("hidden")
        } else {
            this.presenceCountTarget.textContent = `${count} people viewing`
            this.presenceCountTarget.classList.remove("hidden")
        }
    }

    // Called when user starts typing in the reply form
    userTyping() {
        console.log("userTyping called, subscription:", !!this.subscription)
        if (!this.subscription) return

        if (!this.isTyping) {
            this.isTyping = true
            try {
                this.subscription.perform("typing")
            } catch (error) {
                // Silently fail if typing indicator can't be sent
            }
        }

        // Reset the timeout
        if (this.typingTimeout) {
            clearTimeout(this.typingTimeout)
        }

        this.typingTimeout = setTimeout(() => {
            this.isTyping = false
            try {
                if (this.subscription) {
                    this.subscription.perform("stopped_typing")
                }
            } catch (error) {
                // Silently fail
            }
        }, 2000)
    }

    // Show the comment form at the bottom
    showCommentForm() {
        if (this.hasCommentFormTarget) {
            this.commentFormTarget.classList.remove("hidden")
            // Scroll to the form
            this.commentFormTarget.scrollIntoView({ behavior: "smooth", block: "center" })
            // Focus the editor
            const editor = this.commentFormTarget.querySelector("trix-editor")
            if (editor) {
                setTimeout(() => editor.focus(), 100)
            }
        }
    }

    // Hide the comment form
    hideCommentForm() {
        if (this.hasCommentFormTarget) {
            this.commentFormTarget.classList.add("hidden")
        }
    }
}
