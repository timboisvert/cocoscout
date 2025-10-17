import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { showId: Number, status: String }

    connect() {
        this.updateButtons();
    }

    setAvailable() {
        this.updateStatus("available");
    }

    setUnavailable() {
        this.updateStatus("unavailable");
    }

    updateStatus(status) {
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
        this.element.querySelectorAll('.availability-btn').forEach(btn => {
            const selected = btn.getAttribute('data-selected');
            if (selected === this.statusValue) {
                btn.classList.add('bg-pink-500', 'text-white', 'border-pink-500');
                btn.classList.remove('bg-white', 'text-gray-700', 'border-gray-200');
            } else {
                btn.classList.remove('bg-pink-500', 'text-white', 'border-pink-500');
                btn.classList.add('bg-white', 'text-gray-700', 'border-gray-200');
            }
        });
    }
}
