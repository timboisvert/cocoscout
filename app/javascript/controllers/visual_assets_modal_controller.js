import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["logoModal", "posterModal", "posterForm", "posterImage", "posterName", "posterIdField", "posterModalTitle", "posterSubmitButton", "currentPosterPreview"]
    static values = { createPosterPath: String }

    connect() {
        this.escapeListener = (e) => {
            if (e.key === "Escape") {
                this.closeLogoModal()
                this.closePosterModal()
            }
        }
        document.addEventListener("keydown", this.escapeListener)
    }

    disconnect() {
        document.removeEventListener("keydown", this.escapeListener)
    }

    openLogoModal(event) {
        event.preventDefault()
        this.logoModalTarget.classList.remove("hidden")
    }

    closeLogoModal(event) {
        if (event) {
            event.preventDefault()
        }
        this.logoModalTarget.classList.add("hidden")
    }

    openNewPosterModal(event) {
        event.preventDefault()
        // Reset form for new poster
        this.posterFormTarget.reset()
        if (this.hasPosterIdFieldTarget) {
            this.posterIdFieldTarget.value = ""
        }
        this.posterModalTitleTarget.textContent = "Add a Poster"
        this.posterSubmitButtonTarget.textContent = "Add Poster"
        // Hide current poster preview when adding new
        if (this.hasCurrentPosterPreviewTarget) {
            this.currentPosterPreviewTarget.classList.add("hidden")
        }
        // Update form action for create
        this.posterFormTarget.action = this.createPosterPathValue
        this.posterFormTarget.querySelector('input[name="_method"]')?.remove()
        this.posterModalTarget.classList.remove("hidden")
    }

    openEditPosterModal(event) {
        event.preventDefault()
        const button = event.currentTarget
        const posterId = button.dataset.posterId
        const posterName = button.dataset.posterName || ""
        const posterImageUrl = button.dataset.posterImageUrl || ""

        // Set form for editing
        if (this.hasPosterIdFieldTarget) {
            this.posterIdFieldTarget.value = posterId
        }
        if (this.hasPosterNameTarget) {
            this.posterNameTarget.value = posterName
        }
        this.posterModalTitleTarget.textContent = "Edit Poster"
        this.posterSubmitButtonTarget.textContent = "Update Poster"

        // Show current poster preview if URL is available
        if (this.hasCurrentPosterPreviewTarget && posterImageUrl) {
            this.currentPosterPreviewTarget.classList.remove("hidden")
            const img = this.currentPosterPreviewTarget.querySelector("img")
            if (img) {
                img.src = posterImageUrl
            }
        } else if (this.hasCurrentPosterPreviewTarget) {
            this.currentPosterPreviewTarget.classList.add("hidden")
        }

        // Update form action for update and add method override
        this.posterFormTarget.action = button.dataset.editPosterPath

        // Add or update the _method hidden field for PATCH
        let methodField = this.posterFormTarget.querySelector('input[name="_method"]')
        if (!methodField) {
            methodField = document.createElement("input")
            methodField.type = "hidden"
            methodField.name = "_method"
            this.posterFormTarget.prepend(methodField)
        }
        methodField.value = "patch"

        this.posterModalTarget.classList.remove("hidden")
    }

    closePosterModal(event) {
        if (event) {
            event.preventDefault()
        }
        this.posterModalTarget.classList.add("hidden")
        this.posterFormTarget.reset()
        // Hide current poster preview
        if (this.hasCurrentPosterPreviewTarget) {
            this.currentPosterPreviewTarget.classList.add("hidden")
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
