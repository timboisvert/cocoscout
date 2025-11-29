import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "form", "title", "nameInput", "methodInput", "submitButton"]

    openForNew(event) {
        event.preventDefault()
        this.titleTarget.textContent = "Add Role"
        this.formTarget.reset()
        this.formTarget.action = this.element.dataset.createPath
        this.methodInputTarget.value = "post"
        this.submitButtonTarget.textContent = "Add Role"
        this.modalTarget.classList.remove("hidden")
    }

    openForEdit(event) {
        event.preventDefault()
        const button = event.currentTarget
        this.titleTarget.textContent = "Edit Role"
        this.nameInputTarget.value = button.dataset.roleName
        this.formTarget.action = button.dataset.updatePath
        this.methodInputTarget.value = "patch"
        this.submitButtonTarget.textContent = "Update Role"
        this.modalTarget.classList.remove("hidden")
    }

    close(event) {
        if (event.target === this.modalTarget || event.currentTarget.dataset.action === "close") {
            this.modalTarget.classList.add("hidden")
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
