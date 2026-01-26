import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "form", "title", "textInput", "typeSelect", "requiredSelect", "methodInput", "submitButton", "optionsSection", "description", "optionsContainer"]

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

        // Hide options section initially and clear any existing options
        if (this.hasOptionsSectionTarget) {
            this.optionsSectionTarget.classList.add("hidden")
        }
        if (this.hasOptionsContainerTarget) {
            this.clearOptions()
            this.addEmptyOption() // Add one empty option for new questions
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

        // Show options section if needed and populate options
        const needsOptions = button.dataset.questionType === "multiple" || button.dataset.questionType === "ranking"
        if (this.hasOptionsSectionTarget) {
            if (needsOptions) {
                this.optionsSectionTarget.classList.remove("hidden")
            } else {
                this.optionsSectionTarget.classList.add("hidden")
            }
        }

        // Populate options from data attribute
        if (this.hasOptionsContainerTarget && needsOptions) {
            this.clearOptions()
            const optionsData = button.dataset.questionOptions
            if (optionsData) {
                try {
                    const options = JSON.parse(optionsData)
                    if (options.length > 0) {
                        options.forEach(option => this.addOption(option.id, option.text))
                    } else {
                        this.addEmptyOption()
                    }
                } catch (e) {
                    console.error("Failed to parse question options:", e)
                    this.addEmptyOption()
                }
            } else {
                this.addEmptyOption()
            }
        }

        this.modalTarget.classList.remove("hidden")
    }

    clearOptions() {
        if (this.hasOptionsContainerTarget) {
            this.optionsContainerTarget.innerHTML = ""
        }
    }

    addEmptyOption() {
        this.addOption(null, "")
    }

    addOption(id, text) {
        if (!this.hasOptionsContainerTarget) return

        // Use a unique integer index for Rails nested attributes
        const index = id || Math.floor(Date.now() + Math.random() * 1000)
        const idField = id ? `<input type="hidden" name="question[question_options_attributes][${index}][id]" value="${id}">` : ""

        const optionHtml = `
            <div class="nested-fields" data-nested-form-target="target">
                <div class="flex items-center gap-2">
                    ${idField}
                    <input type="text" name="question[question_options_attributes][${index}][text]" value="${this.escapeHtml(text)}" placeholder="Option text" class="block shadow-sm rounded-lg border px-3 py-2 flex-1 border-gray-400">
                    <input type="hidden" name="question[question_options_attributes][${index}][_destroy]" value="false">
                    <button type="button" data-action="nested-form#remove" class="inline-flex items-center justify-center gap-1.5 font-medium transition-colors duration-200 cursor-pointer whitespace-nowrap rounded-lg text-xs px-3 py-1.5 bg-red-600 text-white hover:bg-red-700">
                        <span>Remove</span>
                    </button>
                </div>
            </div>
        `
        this.optionsContainerTarget.insertAdjacentHTML("beforeend", optionHtml)
    }

    escapeHtml(text) {
        const div = document.createElement("div")
        div.textContent = text || ""
        return div.innerHTML
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
