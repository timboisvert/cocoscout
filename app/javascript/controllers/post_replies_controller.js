import { Controller } from "@hotwired/stimulus"

// Handles reply toggles and form visibility for forum posts
export default class extends Controller {
    static targets = ["replyForm", "replies", "toggleButton", "chevron", "count"]
    static values = { postId: Number }

    toggleReplyForm() {
        if (!this.hasReplyFormTarget) return

        const isHidden = this.replyFormTarget.classList.contains("hidden")
        
        if (isHidden) {
            // Show the form and load it via Turbo Frame if not already loaded
            this.replyFormTarget.classList.remove("hidden")
            const frame = this.replyFormTarget.querySelector("turbo-frame")
            if (frame && !frame.src) {
                frame.src = `/my/messages/reply_form?parent_id=${this.postIdValue}`
            }
        } else {
            this.replyFormTarget.classList.add("hidden")
        }
    }

    hideReplyForm() {
        if (this.hasReplyFormTarget) {
            this.replyFormTarget.classList.add("hidden")
        }
    }

    toggleReplies() {
        if (this.hasRepliesTarget) {
            const isHidden = this.repliesTarget.classList.toggle("hidden")

            // Rotate chevron icon
            if (this.hasChevronTarget) {
                if (isHidden) {
                    this.chevronTarget.classList.remove("rotate-180")
                } else {
                    this.chevronTarget.classList.add("rotate-180")
                }
            }
        }
    }

    // Called when a new reply is added via Turbo Stream
    replyAdded() {
        // Show replies section
        if (this.hasRepliesTarget) {
            this.repliesTarget.classList.remove("hidden")
        }

        // Hide reply form
        if (this.hasReplyFormTarget) {
            this.replyFormTarget.classList.add("hidden")
        }

        // Rotate chevron to show expanded state
        if (this.hasChevronTarget) {
            this.chevronTarget.classList.add("rotate-180")
        }
    }
}
