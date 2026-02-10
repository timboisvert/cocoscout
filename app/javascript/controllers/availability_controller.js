import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { showId: Number, status: String, personId: Number, updateUrl: String }
    static targets = ["success", "availableCheck", "availableText", "unavailableCheck", "unavailableText", "noteInput", "noteContainer", "saveButton"]

    connect() {
        // Only update buttons if this is a show row (has showIdValue)
        if (this.hasShowIdValue) {
            this.updateButtons();
        }
    }

    setStatus(event) {
        event.preventDefault();
        const status = event.currentTarget.dataset.availabilityStatus;

        // Find the closest show row element with showIdValue
        const showRow = event.target.closest('[data-availability-show-id-value]');
        if (showRow) {
            const showId = showRow.dataset.availabilityShowIdValue;
            const entityKey = showRow.dataset.availabilityEntityKey;
            this.updateStatusForShow(showId, status, showRow, entityKey);
        }
    }

    updateStatusForShow(showId, status, showRow, entityKey) {
        // Check for custom update URL (used on manage pages)
        const updateUrl = showRow.dataset.availabilityUpdateUrlValue;
        const personId = showRow.dataset.availabilityPersonIdValue;
        const entityType = showRow.dataset.availabilityEntityTypeValue;

        let url, body;
        if (updateUrl && personId) {
            // Admin updating someone else's availability
            url = updateUrl;
            // For audition sessions, use different parameter names
            if (entityKey === "audition_session") {
                body = { availability_session_id: showId, [`availability_${showId}`]: status };
            } else {
                body = { [`availability_${showId}`]: status };
            }
        } else {
            // User updating their own availability
            // Check if this is an audition session (entityKey will be "audition_session")
            if (entityKey === "audition_session") {
                url = `/my/audition_availability/${showId}`;
            } else {
                url = `/my/availability/${showId}`;
            }
            body = { status, entity_key: entityKey, entity_type: entityType };
        }

        fetch(url, {
            method: "PATCH",
            headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content },
            body: JSON.stringify(body)
        })
            .then(r => r.json())
            .then(data => {
                if (data.status) {
                    // Update the data attribute
                    showRow.dataset.availabilityStatusValue = data.status;
                    // Update the buttons in this row
                    this.updateButtonsForRow(showRow, data.status);
                    // Show check icon in the selected button
                    this.showCheckForStatus(showRow, data.status);
                } else if (data.error) {
                    alert(data.error);
                }
            });
    }

    showCheckForStatus(row, status) {
        // Find the check and text elements for the selected status
        const checkEl = row.querySelector(`[data-availability-target="${status}Check"]`);
        const textEl = row.querySelector(`[data-availability-target="${status}Text"]`);

        if (checkEl && textEl) {
            // Hide text, show check
            textEl.classList.add('hidden');
            checkEl.classList.remove('hidden');

            // After 2 seconds, show text and hide check
            setTimeout(() => {
                checkEl.classList.add('hidden');
                textEl.classList.remove('hidden');
            }, 2000);
        }
    }

    updateStatus(status) {
        // Legacy method for individual show updates
        fetch(`/my/availability/${this.showIdValue}`, {
            method: "PATCH",
            headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content },
            body: JSON.stringify({ status })
        })
            .then(r => r.json())
            .then(data => {
                if (data.status) {
                    this.statusValue = data.status;
                    this.updateButtons();
                } else if (data.error) {
                    alert(data.error);
                }
            });
    }

    updateButtons() {
        this.element.querySelectorAll('a[data-availability-status]').forEach(link => {
            const linkStatus = link.dataset.availabilityStatus;
            if (linkStatus === this.statusValue) {
                link.classList.add('bg-pink-500', 'text-white');
                link.classList.remove('bg-white', 'text-gray-700', 'hover:bg-gray-50');
            } else {
                link.classList.remove('bg-pink-500', 'text-white');
                link.classList.add('bg-white', 'text-gray-700', 'hover:bg-gray-50');
            }
        });
    }

    updateButtonsForRow(row, currentStatus) {
        row.querySelectorAll('a[data-availability-status]').forEach(link => {
            const linkStatus = link.dataset.availabilityStatus;
            if (linkStatus === currentStatus) {
                link.classList.add('bg-pink-500', 'text-white');
                link.classList.remove('bg-white', 'text-gray-700', 'hover:bg-gray-50');
            } else {
                link.classList.remove('bg-pink-500', 'text-white');
                link.classList.add('bg-white', 'text-gray-700', 'hover:bg-gray-50');
            }
        });

        // Show/hide note container based on status
        const noteContainer = row.querySelector('[data-availability-target="noteContainer"]');
        if (noteContainer) {
            if (currentStatus === 'available') {
                noteContainer.classList.remove('hidden');
            } else {
                noteContainer.classList.add('hidden');
            }
        }
    }

    showSaveButton(event) {
        const input = event.currentTarget;
        const showRow = input.closest('[data-availability-show-id-value]');
        if (!showRow) return;

        // Hide all other save buttons first
        document.querySelectorAll('[data-availability-target="saveButton"]').forEach(btn => {
            if (!showRow.contains(btn)) {
                btn.classList.add('hidden');
                btn.textContent = 'Save';
                btn.classList.remove('bg-green-500');
                btn.classList.add('bg-pink-500', 'hover:bg-pink-600');
            }
        });

        const saveBtn = showRow.querySelector('[data-availability-target="saveButton"]');
        if (saveBtn) {
            saveBtn.classList.remove('hidden');
        }
    }

    saveNote(event) {
        const button = event.currentTarget;
        const showRow = button.closest('[data-availability-show-id-value]');
        if (!showRow) return;

        const input = showRow.querySelector('[data-availability-target="noteInput"]');
        if (!input) return;

        const showId = showRow.dataset.availabilityShowIdValue;
        const entityKey = showRow.dataset.availabilityEntityKey;
        const entityType = showRow.dataset.availabilityEntityTypeValue;
        const note = input.value.trim();

        fetch(`/my/availability/${showId}/note`, {
            method: "PATCH",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify({ note, entity_key: entityKey, entity_type: entityType })
        })
            .then(r => r.json())
            .then(data => {
                if (data.error) {
                    alert(data.error);
                } else {
                    // Show checkmark feedback
                    const originalText = button.textContent;
                    button.textContent = '✓';
                    button.classList.remove('bg-pink-500', 'hover:bg-pink-600');
                    button.classList.add('bg-green-500');
                    setTimeout(() => {
                        button.classList.add('hidden');
                        button.textContent = originalText;
                        button.classList.remove('bg-green-500');
                        button.classList.add('bg-pink-500', 'hover:bg-pink-600');
                    }, 1500);
                    // Blur the input
                    input.blur();
                }
            });
    }
}
