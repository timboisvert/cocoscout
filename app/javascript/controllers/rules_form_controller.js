import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["allowEdit", "editSection", "editHasCutoff", "editCutoff", "editCutoffMode", "editCutoffHours",
        "allowCancel", "cancelSection", "cancelHasCutoff", "cancelCutoff", "cancelCutoffMode", "cancelCutoffHours"]

    toggleEditSection() {
        if (this.hasEditSectionTarget && this.hasAllowEditTarget) {
            if (this.allowEditTarget.checked) {
                this.editSectionTarget.classList.remove("hidden")
            } else {
                this.editSectionTarget.classList.add("hidden")
            }
        }
    }

    toggleCancelSection() {
        if (this.hasCancelSectionTarget && this.hasAllowCancelTarget) {
            if (this.allowCancelTarget.checked) {
                this.cancelSectionTarget.classList.remove("hidden")
            } else {
                this.cancelSectionTarget.classList.add("hidden")
            }
        }
    }

    toggleEditCutoff() {
        if (this.hasEditCutoffTarget && this.hasEditHasCutoffTarget) {
            if (this.editHasCutoffTarget.checked) {
                this.editCutoffTarget.classList.remove("hidden")
            } else {
                this.editCutoffTarget.classList.add("hidden")
            }
        }
    }

    toggleCancelCutoff() {
        if (this.hasCancelCutoffTarget && this.hasCancelHasCutoffTarget) {
            if (this.cancelHasCutoffTarget.checked) {
                this.cancelCutoffTarget.classList.remove("hidden")
            } else {
                this.cancelCutoffTarget.classList.add("hidden")
            }
        }
    }

    toggleEditCutoffHours() {
        if (this.hasEditCutoffHoursTarget && this.hasEditCutoffModeTarget) {
            const mode = this.editCutoffModeTarget.value
            if (mode === "at_event") {
                this.editCutoffHoursTarget.classList.add("hidden")
            } else {
                this.editCutoffHoursTarget.classList.remove("hidden")
                // Update the label text based on mode
                const label = this.editCutoffHoursTarget.querySelector("span")
                if (label) {
                    label.textContent = mode === "after_event" ? "hours after event" : "hours before event"
                }
            }
        }
    }

    toggleCancelCutoffHours() {
        if (this.hasCancelCutoffHoursTarget && this.hasCancelCutoffModeTarget) {
            const mode = this.cancelCutoffModeTarget.value
            if (mode === "at_event") {
                this.cancelCutoffHoursTarget.classList.add("hidden")
            } else {
                this.cancelCutoffHoursTarget.classList.remove("hidden")
                // Update the label text based on mode
                const label = this.cancelCutoffHoursTarget.querySelector("span")
                if (label) {
                    label.textContent = mode === "after_event" ? "hours after event" : "hours before event"
                }
            }
        }
    }
}
