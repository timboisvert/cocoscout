import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "showSelect", "deleteConfirmModal"]
    static values = { showId: Number, productionId: Number }

    connect() {
        this.boundHandleKeydown = this.handleKeydown.bind(this)
        document.addEventListener("keydown", this.boundHandleKeydown)
    }

    disconnect() {
        document.removeEventListener("keydown", this.boundHandleKeydown)
    }

    handleKeydown(event) {
        if (event.key === "Escape") {
            if (this.hasDeleteConfirmModalTarget && !this.deleteConfirmModalTarget.classList.contains("hidden")) {
                this.cancelDeleteLinkage()
            } else if (this.hasModalTarget && !this.modalTarget.classList.contains("hidden")) {
                this.closeModal()
            }
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

        if (!this.hasShowSelectTarget) {
            alert("No events available to link")
            return
        }

        const showSelect = this.showSelectTarget
        const targetShowId = showSelect.value

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
                "Accept": "text/vnd.turbo-stream.html",
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
                    return response.text().then(text => {
                        throw new Error(`Server error: ${response.status}`)
                    })
                }
                return response.text()
            })
            .then(html => {
                // Turbo will process the stream - updates just the modal body and list
                Turbo.renderStreamMessage(html)
            })
            .catch(error => {
                console.error("Error linking show:", error)
                alert(error.message || "An error occurred while linking the event")
            })
    }

    removeFromLinkage(event) {
        event.preventDefault()

        const targetShowId = event.currentTarget.dataset.showId

        // Get CSRF token
        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        // Build URL - we're removing another show from the linkage
        // Pass requesting_show_id so the server knows which show's view to refresh
        const url = `/manage/productions/${this.productionIdValue}/shows/${targetShowId}/unlink_show?requesting_show_id=${this.showIdValue}`

        fetch(url, {
            method: "DELETE",
            headers: {
                "Accept": "text/vnd.turbo-stream.html",
                "Content-Type": "application/json",
                "X-CSRF-Token": csrfToken
            }
        })
            .then(response => {
                if (!response.ok) {
                    return response.text().then(text => {
                        throw new Error(`Server error: ${response.status}`)
                    })
                }
                return response.text()
            })
            .then(html => {
                // Turbo will process the stream - updates just the modal body and list
                Turbo.renderStreamMessage(html)
            })
            .catch(error => {
                console.error("Error removing show from linkage:", error)
                alert("An error occurred while removing the event from linkage")
            })
    }

    deleteLinkage(event) {
        event.preventDefault()
        if (this.hasDeleteConfirmModalTarget) {
            this.deleteConfirmModalTarget.classList.remove("hidden")
        }
    }

    cancelDeleteLinkage(event) {
        if (event) event.preventDefault()
        if (this.hasDeleteConfirmModalTarget) {
            this.deleteConfirmModalTarget.classList.add("hidden")
        }
    }

    confirmDeleteLinkage(event) {
        event.preventDefault()

        // Get CSRF token
        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        // Build URL
        const url = `/manage/productions/${this.productionIdValue}/shows/${this.showIdValue}/delete_linkage`

        fetch(url, {
            method: "DELETE",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": csrfToken
            }
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
                    // Full page reload since linkage is completely deleted
                    window.location.reload()
                } else if (data.error) {
                    alert(data.error)
                }
            })
            .catch(error => {
                console.error("Error deleting linkage:", error)
                alert("An error occurred while deleting the linkage")
            })
    }
}
