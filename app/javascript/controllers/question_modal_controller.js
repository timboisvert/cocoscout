import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "form", "title", "textInput", "typeSelect", "requiredSelect", "methodInput", "submitButton", "optionsSection", "description"]

    connect() {
        // If there are errors, show the modal
        if (this.element.dataset.hasErrors === "true") {
            this.modalTarget.classList.remove("hidden")
        }
    }

    openForNew(event) {
        event.preventDefault()
        this.titleTarget.textContent = "Add a Question"
        this.descriptionTarget.textContent = this.element.dataset.newDescription || ""
        this.formTarget.reset()
        this.formTarget.action = this.element.dataset.createPath
        this.methodInputTarget.value = "post"
        this.submitButtonTarget.querySelector('span').textContent = "Add Question"

        // Hide options section initially
        if (this.hasOptionsSectionTarget) {
            this.optionsSectionTarget.classList.add("hidden")
        }

        this.modalTarget.classList.remove("hidden")
    }

    openForEdit(event) {
        event.preventDefault()
        const button = event.currentTarget

        this.titleTarget.textContent = "Edit Question"
        this.descriptionTarget.textContent = ""
        this.textInputTarget.value = button.dataset.questionText
        this.typeSelectTarget.value = button.dataset.questionType
        this.requiredSelectTarget.value = button.dataset.questionRequired
        this.formTarget.action = button.dataset.updatePath
        this.methodInputTarget.value = "patch"
        this.submitButtonTarget.querySelector('span').textContent = "Update Question"

        // Show options section if needed
        if (this.hasOptionsSectionTarget) {
            const needsOptions = button.dataset.questionType === "multiple" || button.dataset.questionType === "ranking"
            if (needsOptions) {
                this.optionsSectionTarget.classList.remove("hidden")
            } else {
                this.optionsSectionTarget.classList.add("hidden")
            }
        }

        this.modalTarget.classList.remove("hidden")
    }

    close(event) {
        if (event) {
            event.preventDefault()
        }
        this.modalTarget.classList.add("hidden")
    }

    stopPropagation(event) {
        event.stopPropagation()
    }
}
