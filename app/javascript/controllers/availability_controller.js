import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { showId: Number, status: String }

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
            this.updateStatusForShow(showId, status, showRow);
        }
    }

    markAllAvailable(event) {
        event.preventDefault();
        this.markAllShows('available');
    }

    markAllUnavailable(event) {
        event.preventDefault();
        this.markAllShows('unavailable');
    }

    markAllShows(status) {
        // Find all show rows on the page
        const showRows = this.element.querySelectorAll('[data-availability-show-id-value]');

        showRows.forEach(showRow => {
            const showId = showRow.dataset.availabilityShowIdValue;
            this.updateStatusForShow(showId, status, showRow);
        });
    }

    updateStatusForShow(showId, status, showRow) {
        fetch(`/my/availability/${showId}`, {
            method: "PATCH",
            headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content },
            body: JSON.stringify({ status })
        })
            .then(r => r.json())
            .then(data => {
                if (data.status) {
                    // Update the data attribute
                    showRow.dataset.availabilityStatusValue = data.status;
                    // Update the buttons in this row
                    this.updateButtonsForRow(showRow, data.status);
                } else if (data.error) {
                    alert(data.error);
                }
            });
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
    }
}
