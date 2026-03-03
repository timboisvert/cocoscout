import { Controller } from "@hotwired/stimulus"

/**
 * Controller for the new contract wizard's contractor selection.
 * Handles selecting existing contractors and creating new ones via modal.
 */
export default class extends Controller {
    static targets = ["select", "modal", "name", "email", "phone", "address", "error", "submitBtn", "form", "contractorSection"]
    static values = { createUrl: String }

    connect() {
        this.keyHandler = this.handleKeydown.bind(this)
    }

    disconnect() {
        document.removeEventListener('keydown', this.keyHandler)
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.closeModal()
        }
    }

    openModal(event) {
        event.preventDefault()
        this.clearModalForm()
        this.modalTarget.classList.remove('hidden')
        document.addEventListener('keydown', this.keyHandler)
        // Focus the name field
        setTimeout(() => {
            if (this.hasNameTarget) {
                this.nameTarget.focus()
            }
        }, 100)
    }

    closeModal() {
        this.modalTarget.classList.add('hidden')
        document.removeEventListener('keydown', this.keyHandler)
    }

    closeOnBackdrop(event) {
        if (event.target === event.currentTarget) {
            this.closeModal()
        }
    }

    stopPropagation(event) {
        event.stopPropagation()
    }

    clearModalForm() {
        if (this.hasNameTarget) this.nameTarget.value = ""
        if (this.hasEmailTarget) this.emailTarget.value = ""
        if (this.hasPhoneTarget) this.phoneTarget.value = ""
        if (this.hasAddressTarget) this.addressTarget.value = ""
        if (this.hasErrorTarget) {
            this.errorTarget.classList.add('hidden')
            this.errorTarget.textContent = ""
        }
    }

    async createContractor(event) {
        event.preventDefault()

        const name = this.hasNameTarget ? this.nameTarget.value.trim() : ""
        if (!name) {
            this.showError("Name is required")
            return
        }

        // Disable submit button
        if (this.hasSubmitBtnTarget) {
            this.submitBtnTarget.disabled = true
            this.submitBtnTarget.textContent = "Creating..."
        }

        try {
            const response = await fetch(this.createUrlValue, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'X-CSRF-Token': this.getCSRFToken()
                },
                body: JSON.stringify({
                    contractor: {
                        name: name,
                        email: this.hasEmailTarget ? this.emailTarget.value.trim() : "",
                        phone: this.hasPhoneTarget ? this.phoneTarget.value.trim() : "",
                        address: this.hasAddressTarget ? this.addressTarget.value.trim() : ""
                    }
                })
            })

            const data = await response.json()

            if (response.ok) {
                // Add the new contractor to the select dropdown
                this.addContractorToSelect(data.id, data.name)
                // Close the modal
                this.closeModal()
            } else {
                this.showError(data.errors ? data.errors.join(", ") : "Failed to create contractor")
            }
        } catch (error) {
            console.error("Error creating contractor:", error)
            this.showError("An error occurred. Please try again.")
        } finally {
            // Re-enable submit button
            if (this.hasSubmitBtnTarget) {
                this.submitBtnTarget.disabled = false
                this.submitBtnTarget.textContent = "Create Contractor"
            }
        }
    }

    addContractorToSelect(id, name) {
        if (!this.hasSelectTarget) return

        const select = this.selectTarget

        // If the select is a hidden input (no contractors existed), build a real select
        if (select.tagName === 'INPUT') {
            this.replaceEmptyStateWithSelect(id, name)
            return
        }

        // Create new option
        const option = document.createElement('option')
        option.value = id
        option.textContent = name

        // Insert alphabetically
        let inserted = false
        for (let i = 1; i < select.options.length; i++) { // Start at 1 to skip placeholder
            if (select.options[i].textContent.toLowerCase() > name.toLowerCase()) {
                select.add(option, i)
                inserted = true
                break
            }
        }
        if (!inserted) {
            select.add(option)
        }

        // Select the new contractor
        select.value = id
    }

    replaceEmptyStateWithSelect(id, name) {
        if (!this.hasContractorSectionTarget) {
            window.location.reload()
            return
        }

        const section = this.contractorSectionTarget
        section.innerHTML = `
            <label for="contractor_id" class="block text-sm font-medium text-gray-900 mb-1.5">
                Contractor
                <span class="text-pink-500">*</span>
            </label>
            <select name="contract[contractor_id]"
                    id="contractor_id"
                    required
                    data-new-contract-contractor-target="select"
                    class="block w-full px-3 py-2.5 bg-white border border-gray-300 rounded-lg shadow-sm text-gray-900 focus:outline-none focus:ring-2 focus:ring-pink-500 focus:border-pink-500 transition">
                <option value="">-- Choose a contractor --</option>
                <option value="${id}" selected>${this.escapeHtml(name)}</option>
            </select>
            <div class="mt-2">
                <button type="button"
                        data-action="click->new-contract-contractor#openModal"
                        class="inline-flex items-center gap-1.5 text-sm text-pink-600 hover:text-pink-700 font-medium">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>
                    Create new contractor
                </button>
            </div>
        `
    }

    escapeHtml(text) {
        const div = document.createElement('div')
        div.textContent = text
        return div.innerHTML
    }

    showError(message) {
        if (this.hasErrorTarget) {
            this.errorTarget.textContent = message
            this.errorTarget.classList.remove('hidden')
        }
    }

    getCSRFToken() {
        const metaTag = document.querySelector('meta[name="csrf-token"]')
        return metaTag ? metaTag.content : ''
    }
}
