import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "form", "personName", "personHeadshot", "personBox", "slotList", "submitButton"]

    connect() {
        // Controller is ready
    }

    open(event) {
        event.preventDefault();

        const button = event.currentTarget;
        const details = {
            registrationId: button.dataset.registrationId,
            personName: button.dataset.personName,
            personInitial: button.dataset.personInitial,
            personHeadshotUrl: button.dataset.personHeadshotUrl,
            currentSlotId: button.dataset.currentSlotId,
            formActionUrl: button.dataset.formActionUrl
        };

        this.openWithDetails(details);
    }

    openWithDetails(details) {
        const { registrationId, personName, personInitial, personHeadshotUrl, currentSlotId, formActionUrl } = details;

        // Update the person name display
        if (this.hasPersonNameTarget) {
            this.personNameTarget.textContent = personName;
        }

        // Update the person headshot/initial
        if (this.hasPersonHeadshotTarget) {
            if (personHeadshotUrl) {
                this.personHeadshotTarget.innerHTML = `<img src="${personHeadshotUrl}" class="w-10 h-10 rounded-lg object-cover" alt="${personName}">`;
            } else {
                this.personHeadshotTarget.innerHTML = personInitial || personName.charAt(0).toUpperCase();
            }
        }

        // Set the form action URL
        if (this.hasFormTarget) {
            this.formTarget.action = formActionUrl;
        }

        // Disable the current slot and enable others
        if (this.hasSlotListTarget) {
            const labels = this.slotListTarget.querySelectorAll('label[data-slot-id]');
            labels.forEach(label => {
                const slotId = label.dataset.slotId;
                const radio = label.querySelector('input[type="radio"]');

                if (slotId === String(currentSlotId)) {
                    // This is the current slot - disable it and mark as current
                    label.classList.add('opacity-50', 'cursor-not-allowed');
                    label.classList.remove('hover:bg-pink-50', 'cursor-pointer');
                    if (radio) {
                        radio.disabled = true;
                        radio.checked = false;
                    }
                    // Update the middle section to show "Current slot"
                    const middleDiv = label.querySelector('.flex-1');
                    if (middleDiv) {
                        middleDiv.innerHTML = '<span class="text-sm text-pink-600 font-medium">Current slot</span>';
                    }
                } else {
                    // Reset to original state - ensure it's enabled
                    label.classList.remove('opacity-50', 'cursor-not-allowed');
                    label.classList.add('hover:bg-pink-50', 'cursor-pointer');
                    if (radio) {
                        radio.disabled = false;
                    }
                }
            });
        }

        // Reset and disable submit button
        if (this.hasSubmitButtonTarget) {
            this.submitButtonTarget.disabled = true;
        }

        // Uncheck all radios
        const radios = this.element.querySelectorAll('input[type="radio"]');
        radios.forEach(r => r.checked = false);

        // Show the modal
        this.modalTarget.classList.remove("hidden");
    }

    close(event) {
        // If triggered by escape key, only close if modal is visible
        if (event && event.type === 'keydown') {
            if (this.modalTarget.classList.contains('hidden')) {
                return;
            }
        }
        this.modalTarget.classList.add("hidden");
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    selectSlot(event) {
        // Enable submit button when a slot is selected
        if (this.hasSubmitButtonTarget) {
            this.submitButtonTarget.disabled = false;
        }
    }
}
