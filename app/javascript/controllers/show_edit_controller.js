import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["eventTypeSelect", "sectionTitle", "castingEnabledCheckbox", "publicProfileCheckbox", "publicProfileContent"]
    static values = { castingDefaults: Array }

    connect() {
        this.updateTitle()
        this.updatePublicProfileVisibility()
        // Don't update casting default on connect for edit forms - the value is already set from the database
    }

    updateTitle() {
        if (!this.hasEventTypeSelectTarget || !this.hasSectionTitleTarget) return

        const eventType = this.eventTypeSelectTarget.value
        const eventTypeLabel = this.eventTypeSelectTarget.options[this.eventTypeSelectTarget.selectedIndex].text

        this.sectionTitleTarget.textContent = `Optional ${eventTypeLabel} Settings`
    }

    updatePublicProfileVisibility() {
        if (!this.hasPublicProfileCheckboxTarget || !this.hasPublicProfileContentTarget) return

        const enabled = this.publicProfileCheckboxTarget.checked
        if (enabled) {
            this.publicProfileContentTarget.classList.remove('hidden')
        } else {
            this.publicProfileContentTarget.classList.add('hidden')
        }
    }

    publicProfileToggled() {
        this.updatePublicProfileVisibility()
    }

    updateCastingDefault() {
        if (!this.hasEventTypeSelectTarget || !this.hasCastingEnabledCheckboxTarget) return

        const eventType = this.eventTypeSelectTarget.value

        // Only update if the checkbox hasn't been manually changed
        if (this.castingEnabledCheckboxTarget.dataset.manuallyChanged !== 'true') {
            // Check if this event type should have casting enabled by default
            const castingDefaults = this.hasCastingDefaultsValue ? this.castingDefaultsValue : ['show']
            this.castingEnabledCheckboxTarget.checked = castingDefaults.includes(eventType)
        }
    }

    eventTypeChanged() {
        this.updateTitle()
        this.updateCastingDefault()
    }

    castingCheckboxChanged() {
        // Mark that the checkbox has been manually changed
        this.castingEnabledCheckboxTarget.dataset.manuallyChanged = 'true'
    }

    // The move modal is driven by the separate show-actions controller (it
    // lazy-loads productions). It lives outside this form, so reach it with a
    // window event instead of a Stimulus action.
    openMoveModal() {
        window.dispatchEvent(new CustomEvent('show-actions:open-move-modal'))
    }
}
