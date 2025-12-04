import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["logoModal", "posterModal", "posterForm", "posterImage", "posterName", "posterIdField", "posterModalTitle", "posterSubmitButton"]

    connect() {
        this.escapeListener = (e) => {
            if (e.key === "Escape") {
                this.closeLogoModal()
                this.closePosterModal()
            }
        }
    }

    disconnect() {
        document.removeEventListener("keydown", this.escapeListener)
    }

    openLogoModal(event) {
        event.preventDefault()
        this.logoModalTarget.classList.remove("hidden")
        document.addEventListener("keydown", this.escapeListener)
    }

    closeLogoModal(event) {
        if (event) {
            event.preventDefault()
        }
        this.logoModalTarget.classList.add("hidden")
        document.removeEventListener("keydown", this.escapeListener)
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
        // Update form action for create
        this.posterFormTarget.action = this.element.dataset.createPosterPath
        this.posterFormTarget.querySelector('input[name="_method"]')?.remove()
        this.posterModalTarget.classList.remove("hidden")
        document.addEventListener("keydown", this.escapeListener)
    }

    openEditPosterModal(event) {
        event.preventDefault()
        const button = event.currentTarget
        const posterId = button.dataset.posterId
        const posterName = button.dataset.posterName || ""

        // Set form for editing
        if (this.hasPosterIdFieldTarget) {
            this.posterIdFieldTarget.value = posterId
        }
        if (this.hasPosterNameTarget) {
            this.posterNameTarget.value = posterName
        }
        this.posterModalTitleTarget.textContent = "Edit Poster"
        this.posterSubmitButtonTarget.textContent = "Update Poster"

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
        document.addEventListener("keydown", this.escapeListener)
    }

    closePosterModal(event) {
        if (event) {
            event.preventDefault()
        }
        this.posterModalTarget.classList.add("hidden")
        this.posterFormTarget.reset()
        document.removeEventListener("keydown", this.escapeListener)
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
