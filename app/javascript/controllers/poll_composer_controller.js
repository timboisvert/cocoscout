import { Controller } from "@hotwired/stimulus"

/**
 * Poll Composer Controller
 *
 * Manages the poll form within the compose message modal.
 * Handles adding/removing poll options, toggling poll visibility,
 * and configuring multiple-vote settings.
 */
export default class extends Controller {
    static targets = [
        "section",       // The poll form section (hidden/shown)
        "toggleButton",  // The "Add Poll" button
        "question",      // Poll question input
        "optionsList",   // Container for option inputs
        "optionTemplate", // Template for new options
        "multipleVotes", // Checkbox for allowing multiple votes
        "maxVotes",      // Max votes number input
        "maxVotesHidden", // Hidden default max_votes input
        "maxVotesWrapper" // Wrapper for max votes (shown when multiple votes enabled)
    ]

    connect() {
        this.optionCounter = 2 // Start with 2 default options
    }

    toggle() {
        const section = this.sectionTarget
        const isHidden = section.classList.contains("hidden")

        if (isHidden) {
            section.classList.remove("hidden")
            this.toggleButtonTarget.classList.add("hidden")
            this.element.classList.add("w-full")
            // Focus the question input
            setTimeout(() => this.questionTarget.focus(), 100)
        } else {
            this.removePoll()
        }
    }

    removePoll() {
        this.sectionTarget.classList.add("hidden")
        this.toggleButtonTarget.classList.remove("hidden")
        this.element.classList.remove("w-full")

        // Reset form fields
        this.questionTarget.value = ""
        this.multipleVotesTarget.checked = false
        this.maxVotesWrapperTarget.classList.add("hidden")
        this.maxVotesTarget.value = "2"
        this.maxVotesHiddenTarget.disabled = false

        // Reset to 2 default options
        this.optionsListTarget.innerHTML = ""
        this.optionCounter = 0
        this.addOption()
        this.addOption()
    }

    addOption() {
        this.optionCounter++
        const index = this.optionCounter

        const wrapper = document.createElement("div")
        wrapper.className = "flex items-center gap-2 group"
        wrapper.dataset.pollComposerTarget = "optionItem"

        wrapper.innerHTML = `
            <div class="flex-1 relative">
                <input type="text"
                       name="message_poll[message_poll_options_attributes][${index}][text]"
                       placeholder="Option ${this.optionsListTarget.children.length + 1}"
                       class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm text-gray-900 placeholder-gray-400 focus:border-pink-500 focus:ring-2 focus:ring-pink-500/20 focus:outline-none transition-colors">
                <input type="hidden"
                       name="message_poll[message_poll_options_attributes][${index}][position]"
                       value="${this.optionsListTarget.children.length}">
            </div>
            <button type="button"
                    class="opacity-0 group-hover:opacity-100 p-1 text-gray-400 hover:text-red-500 transition-all cursor-pointer"
                    data-action="click->poll-composer#removeOption"
                    title="Remove option">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                </svg>
            </button>
        `

        this.optionsListTarget.appendChild(wrapper)
        // Focus the new input
        const input = wrapper.querySelector("input[type='text']")
        setTimeout(() => input.focus(), 50)

        this.updateRemoveButtons()
    }

    removeOption(event) {
        const optionItem = event.currentTarget.closest("[data-poll-composer-target='optionItem']")
        if (optionItem && this.optionsListTarget.children.length > 2) {
            optionItem.remove()
            this.updatePlaceholders()
            this.updateRemoveButtons()
        }
    }

    updatePlaceholders() {
        const options = this.optionsListTarget.querySelectorAll("input[type='text']")
        options.forEach((input, index) => {
            input.placeholder = `Option ${index + 1}`
        })
        // Update position hidden fields
        const positions = this.optionsListTarget.querySelectorAll("input[type='hidden'][name*='[position]']")
        positions.forEach((input, index) => {
            input.value = index
        })
    }

    updateRemoveButtons() {
        const items = this.optionsListTarget.children
        const buttons = this.optionsListTarget.querySelectorAll("button")
        buttons.forEach(btn => {
            if (items.length <= 2) {
                btn.classList.add("invisible")
            } else {
                btn.classList.remove("invisible")
            }
        })
    }

    toggleMultipleVotes() {
        if (this.multipleVotesTarget.checked) {
            this.maxVotesWrapperTarget.classList.remove("hidden")
            // Disable hidden default so the visible input takes precedence
            this.maxVotesHiddenTarget.disabled = true
        } else {
            this.maxVotesWrapperTarget.classList.add("hidden")
            this.maxVotesTarget.value = "2"
            // Re-enable hidden default (value=1)
            this.maxVotesHiddenTarget.disabled = false
        }
    }
}
