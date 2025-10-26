import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["select", "success"]

    connect() {
        // nothing needed
    }

    change(event) {
        const select = this.selectTarget
        const userId = select.dataset.userId
        const productionId = select.dataset.productionId
        const role = select.value
        const url = select.dataset.url
        const token = document.querySelector('meta[name="csrf-token"]').getAttribute('content')

        fetch(url, {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': token,
                'Accept': 'application/json'
            },
            body: JSON.stringify({ user_id: userId, production_id: productionId, role: role })
        })
            .then(response => {
                if (!response.ok) throw new Error('Network error')
                return response.json()
            })
            .then(() => {
                this.showSuccess()
            })
            .catch(() => {
                // Optionally show error
            })
    }

    showSuccess() {
        if (this.hasSuccessTarget) {
            this.successTarget.classList.remove('hidden')
            setTimeout(() => {
                this.successTarget.classList.add('hidden')
            }, 2000)
        }
    }
}
