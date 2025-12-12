import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "showSelect"]
    static values = { showId: Number, productionId: Number }

    connect() {
        console.log("show-linkage controller connected", {
            showId: this.showIdValue,
            productionId: this.productionIdValue,
            hasModalTarget: this.hasModalTarget,
            hasShowSelectTarget: this.hasShowSelectTarget
        })
        this.boundHandleKeydown = this.handleKeydown.bind(this)
        document.addEventListener("keydown", this.boundHandleKeydown)
    }

    disconnect() {
        document.removeEventListener("keydown", this.boundHandleKeydown)
    }

    handleKeydown(event) {
        if (event.key === "Escape" && this.hasModalTarget && !this.modalTarget.classList.contains("hidden")) {
            this.closeModal()
        }
    }

    openModal(event) {
        event.preventDefault()
        if (this.hasModalTarget) {
            this.modalTarget.classList.remove("hidden")
            document.body.style.overflow = "hidden"
        }
    }

    closeModal(event) {
        if (event) event.preventDefault()
        if (this.hasModalTarget) {
            this.modalTarget.classList.add("hidden")
            document.body.style.overflow = ""
        }
    }

    linkShow(event) {
        event.preventDefault()
        console.log("linkShow called", { hasShowSelectTarget: this.hasShowSelectTarget })

        if (!this.hasShowSelectTarget) {
            alert("No events available to link")
            return
        }

        const showSelect = this.showSelectTarget
        const targetShowId = showSelect.value
        console.log("Selected show ID:", targetShowId)

        if (!targetShowId) {
            alert("Please select an event to link")
            return
        }

        // Always use sibling role
        const linkageRole = "sibling"

        // Get CSRF token
        const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
        if (!csrfToken) {
            alert("Authentication error. Please refresh the page.")
            return
        }

        // Build URL
        const url = `/manage/productions/${this.productionIdValue}/shows/${this.showIdValue}/link_show`

        fetch(url, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": csrfToken
            },
            body: JSON.stringify({
                target_show_id: targetShowId,
                linkage_role: linkageRole
            })
        })
        .then(response => {
            if (!response.ok) {
                return response.json().then(data => {
                    throw new Error(data.error || `Server error: ${response.status}`)
                })
            }
            return response.json()
        })
        .then(data => {
            if (data.success) {
                // Reload the page to show updated linkage
                window.location.href = data.redirect_url
            } else if (data.error) {
                alert(data.error)
            }
        })
        .catch(error => {
            console.error("Error linking show:", error)
            alert(error.message || "An error occurred while linking the event")
        })
    }

    unlinkShow(event) {
        event.preventDefault()

        if (!confirm("Are you sure you want to remove this event from the linkage?")) {
            return
        }

        // Get CSRF token
        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        // Build URL
        const url = `/manage/productions/${this.productionIdValue}/shows/${this.showIdValue}/unlink_show`

        fetch(url, {
            method: "DELETE",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": csrfToken
            }
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                // Reload the page to show updated state
                window.location.href = data.redirect_url
            } else if (data.error) {
                alert(data.error)
            }
        })
        .catch(error => {
            console.error("Error unlinking show:", error)
            alert("An error occurred while unlinking the event")
        })
    }

    removeFromLinkage(event) {
        event.preventDefault()

        const targetShowId = event.currentTarget.dataset.showId

        if (!confirm("Are you sure you want to remove this event from the linkage?")) {
            return
        }

        // Get CSRF token
        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        // Build URL - we're removing another show from the linkage
        const url = `/manage/productions/${this.productionIdValue}/shows/${targetShowId}/unlink_show`

        fetch(url, {
            method: "DELETE",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": csrfToken
            }
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                // Reload the current page (not the target's redirect)
                window.location.reload()
            } else if (data.error) {
                alert(data.error)
            }
        })
        .catch(error => {
            console.error("Error removing show from linkage:", error)
            alert("An error occurred while removing the event from linkage")
        })
    }
}
