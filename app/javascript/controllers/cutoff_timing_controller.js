import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        // Edit cutoff targets
        "allowEdit", "editSection", "editHasCutoff", "editCutoff",
        "editModeAtEvent", "editModeBefore", "editModeAfter",
        "editBeforeFields", "editAfterFields",
        // Cancel cutoff targets
        "allowCancel", "cancelSection", "cancelHasCutoff", "cancelCutoff",
        "cancelModeAtEvent", "cancelModeBefore", "cancelModeAfter",
        "cancelBeforeFields", "cancelAfterFields"
    ]

    // Toggle visibility of edit section when "Allow edits" is toggled
    toggleEditSection() {
        if (this.hasEditSectionTarget && this.hasAllowEditTarget) {
            if (this.allowEditTarget.checked) {
                this.editSectionTarget.classList.remove("hidden")
            } else {
                this.editSectionTarget.classList.add("hidden")
            }
        }
    }

    // Toggle visibility of cancel section when "Allow cancellations" is toggled
    toggleCancelSection() {
        if (this.hasCancelSectionTarget && this.hasAllowCancelTarget) {
            if (this.allowCancelTarget.checked) {
                this.cancelSectionTarget.classList.remove("hidden")
            } else {
                this.cancelSectionTarget.classList.add("hidden")
            }
        }
    }

    // Toggle visibility of edit cutoff options when "Set a cutoff for edits" is toggled
    toggleEditCutoff() {
        if (this.hasEditCutoffTarget && this.hasEditHasCutoffTarget) {
            if (this.editHasCutoffTarget.checked) {
                this.editCutoffTarget.classList.remove("hidden")
            } else {
                this.editCutoffTarget.classList.add("hidden")
            }
        }
    }

    // Toggle visibility of cancel cutoff options when "Set a cutoff for cancellations" is toggled
    toggleCancelCutoff() {
        if (this.hasCancelCutoffTarget && this.hasCancelHasCutoffTarget) {
            if (this.cancelHasCutoffTarget.checked) {
                this.cancelCutoffTarget.classList.remove("hidden")
            } else {
                this.cancelCutoffTarget.classList.add("hidden")
            }
        }
    }

    // Select edit cutoff mode (at_event, before_event, after_event)
    selectEditMode(event) {
        const value = event.currentTarget.dataset.value

        // Update radio buttons
        if (this.hasEditModeAtEventTarget) this.editModeAtEventTarget.checked = (value === "at_event")
        if (this.hasEditModeBeforeTarget) this.editModeBeforeTarget.checked = (value === "before_event")
        if (this.hasEditModeAfterTarget) this.editModeAfterTarget.checked = (value === "after_event")

        // Update styling on parent containers
        this.updateEditModeStyles(value)

        // Show/hide fields and enable/disable inputs based on selection
        if (this.hasEditBeforeFieldsTarget) {
            const isHidden = value !== "before_event"
            this.editBeforeFieldsTarget.classList.toggle("hidden", isHidden)
            this.editBeforeFieldsTarget.querySelectorAll("input").forEach(input => input.disabled = isHidden)
        }
        if (this.hasEditAfterFieldsTarget) {
            const isHidden = value !== "after_event"
            this.editAfterFieldsTarget.classList.toggle("hidden", isHidden)
            this.editAfterFieldsTarget.querySelectorAll("input").forEach(input => input.disabled = isHidden)
        }
    }

    // Select cancel cutoff mode (at_event, before_event, after_event)
    selectCancelMode(event) {
        const value = event.currentTarget.dataset.value

        // Update radio buttons
        if (this.hasCancelModeAtEventTarget) this.cancelModeAtEventTarget.checked = (value === "at_event")
        if (this.hasCancelModeBeforeTarget) this.cancelModeBeforeTarget.checked = (value === "before_event")
        if (this.hasCancelModeAfterTarget) this.cancelModeAfterTarget.checked = (value === "after_event")

        // Update styling on parent containers
        this.updateCancelModeStyles(value)

        // Show/hide fields and enable/disable inputs based on selection
        if (this.hasCancelBeforeFieldsTarget) {
            const isHidden = value !== "before_event"
            this.cancelBeforeFieldsTarget.classList.toggle("hidden", isHidden)
            this.cancelBeforeFieldsTarget.querySelectorAll("input").forEach(input => input.disabled = isHidden)
        }
        if (this.hasCancelAfterFieldsTarget) {
            const isHidden = value !== "after_event"
            this.cancelAfterFieldsTarget.classList.toggle("hidden", isHidden)
            this.cancelAfterFieldsTarget.querySelectorAll("input").forEach(input => input.disabled = isHidden)
        }
    }

    updateEditModeStyles(selectedValue) {
        // Find all edit mode options and update their styles
        const options = this.editCutoffTarget.querySelectorAll("[data-value]")
        options.forEach(option => {
            const isSelected = option.dataset.value === selectedValue
            option.classList.toggle("border-pink-500", isSelected)
            option.classList.toggle("bg-pink-50", isSelected)
            option.classList.toggle("border-gray-200", !isSelected)
        })
    }

    updateCancelModeStyles(selectedValue) {
        // Find all cancel mode options and update their styles
        const options = this.cancelCutoffTarget.querySelectorAll("[data-value]")
        options.forEach(option => {
            const isSelected = option.dataset.value === selectedValue
            option.classList.toggle("border-pink-500", isSelected)
            option.classList.toggle("bg-pink-50", isSelected)
            option.classList.toggle("border-gray-200", !isSelected)
        })
    }
}
