import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["addModal", "editModal", "addForm", "editForm",
        "addErrorContainer", "addErrorList",
        "editErrorContainer", "editErrorList",
        "editLocationId", "editName", "editAddress1", "editAddress2",
        "editCity", "editState", "editPostalCode", "editNotes", "editDefault"]

    connect() {
        this.escapeListener = (e) => {
            if (e.key === "Escape") {
                this.closeAddModal()
                this.closeEditModal()
            }
        }
        document.addEventListener("keydown", this.escapeListener)
    }

    disconnect() {
        document.removeEventListener("keydown", this.escapeListener)
    }

    openAddModal(event) {
        event.preventDefault()
        if (this.hasAddFormTarget) {
            this.addFormTarget.reset()
        }
        this.clearAddErrors()
        if (this.hasAddModalTarget) {
            this.addModalTarget.classList.remove("hidden")
        }
    }

    closeAddModal(event) {
        if (event) event.preventDefault()
        if (this.hasAddModalTarget) {
            this.addModalTarget.classList.add("hidden")
        }
    }

    openEditModal(event) {
        event.preventDefault()
        const button = event.currentTarget

        // Populate form with location data
        if (this.hasEditLocationIdTarget) {
            this.editLocationIdTarget.value = button.dataset.locationId
        }
        if (this.hasEditNameTarget) {
            this.editNameTarget.value = button.dataset.locationName || ""
        }
        if (this.hasEditAddress1Target) {
            this.editAddress1Target.value = button.dataset.locationAddress1 || ""
        }
        if (this.hasEditAddress2Target) {
            this.editAddress2Target.value = button.dataset.locationAddress2 || ""
        }
        if (this.hasEditCityTarget) {
            this.editCityTarget.value = button.dataset.locationCity || ""
        }
        if (this.hasEditStateTarget) {
            this.editStateTarget.value = button.dataset.locationState || ""
        }
        if (this.hasEditPostalCodeTarget) {
            this.editPostalCodeTarget.value = button.dataset.locationPostalCode || ""
        }
        if (this.hasEditNotesTarget) {
            this.editNotesTarget.value = button.dataset.locationNotes || ""
        }
        if (this.hasEditDefaultTarget) {
            this.editDefaultTarget.checked = button.dataset.locationDefault === "true"
        }

        // Update form action
        if (this.hasEditFormTarget) {
            this.editFormTarget.action = button.dataset.editPath
        }

        this.clearEditErrors()
        if (this.hasEditModalTarget) {
            this.editModalTarget.classList.remove("hidden")
        }
    }

    closeEditModal(event) {
        if (event) event.preventDefault()
        if (this.hasEditModalTarget) {
            this.editModalTarget.classList.add("hidden")
        }
    }

    clearAddErrors() {
        if (this.hasAddErrorContainerTarget) {
            this.addErrorContainerTarget.classList.add("hidden")
            this.addErrorListTarget.innerHTML = ""
        }
    }

    clearEditErrors() {
        if (this.hasEditErrorContainerTarget) {
            this.editErrorContainerTarget.classList.add("hidden")
            this.editErrorListTarget.innerHTML = ""
        }
    }

    async submitAddForm(event) {
        event.preventDefault()
        const formData = new FormData(this.addFormTarget)

        try {
            const response = await fetch(this.addFormTarget.action, {
                method: "POST",
                body: formData,
                headers: { "Accept": "application/json" }
            })

            if (response.ok) {
                // Reload the page to show the new location
                window.location.reload()
            } else {
                const data = await response.json()
                if (data.errors) {
                    this.displayAddErrors(data.errors)
                }
            }
        } catch (error) {
            console.error("Error submitting location form:", error)
        }
    }

    async submitEditForm(event) {
        event.preventDefault()
        const formData = new FormData(this.editFormTarget)

        try {
            const response = await fetch(this.editFormTarget.action, {
                method: "PATCH",
                body: formData,
                headers: { "Accept": "application/json" }
            })

            if (response.ok) {
                // Reload the page to show the updated location
                window.location.reload()
            } else {
                const data = await response.json()
                if (data.errors) {
                    this.displayEditErrors(data.errors)
                }
            }
        } catch (error) {
            console.error("Error submitting location form:", error)
        }
    }

    displayAddErrors(errors) {
        if (this.hasAddErrorContainerTarget && this.hasAddErrorListTarget) {
            this.addErrorContainerTarget.classList.remove("hidden")
            this.addErrorListTarget.innerHTML = ""
            Object.entries(errors).forEach(([field, messages]) => {
                messages.forEach(message => {
                    const li = document.createElement("li")
                    li.textContent = `${this.formatFieldName(field)} ${message}`
                    this.addErrorListTarget.appendChild(li)
                })
            })
        }
    }

    displayEditErrors(errors) {
        if (this.hasEditErrorContainerTarget && this.hasEditErrorListTarget) {
            this.editErrorContainerTarget.classList.remove("hidden")
            this.editErrorListTarget.innerHTML = ""
            Object.entries(errors).forEach(([field, messages]) => {
                messages.forEach(message => {
                    const li = document.createElement("li")
                    li.textContent = `${this.formatFieldName(field)} ${message}`
                    this.editErrorListTarget.appendChild(li)
                })
            })
        }
    }

    formatFieldName(field) {
        const names = {
            "name": "Name",
            "address1": "Street Address Line 1",
            "address2": "Street Address Line 2",
            "city": "City",
            "state": "State/Province",
            "postal_code": "Zip/Postal Code",
            "notes": "Notes"
        }
        return names[field] || field.charAt(0).toUpperCase() + field.slice(1).replace(/_/g, " ")
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
