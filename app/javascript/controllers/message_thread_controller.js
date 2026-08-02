import { Controller } from "@hotwired/stimulus"

// Comment-form UI for a message thread. Live updates (new replies appearing
// without a reload, typing indicators, "X viewing" presence) previously rode
// ActionCable; that layer has been removed, so a thread now reflects new
// replies on reload. This controller keeps the local UI: opening/closing the
// comment form and deep-link auto-open.
export default class extends Controller {
    static targets = ["commentForm", "commentBody"]
    static values = {
        focusComment: Boolean
    }

    connect() {
        // Auto-open the comment form when deep-linked (?focus_comment).
        if (this.focusCommentValue) {
            setTimeout(() => this.showCommentForm(), 150)
        }
    }

    // Retained as a no-op so the `trix-change->message-thread#userTyping` action
    // refs in the thread views stay valid now that typing broadcasts are gone.
    userTyping() {}

    // Show the comment form at the bottom
    showCommentForm() {
        if (this.hasCommentFormTarget) {
            this.commentFormTarget.classList.remove("hidden")
            this.commentFormTarget.scrollIntoView({ behavior: "smooth", block: "center" })
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
