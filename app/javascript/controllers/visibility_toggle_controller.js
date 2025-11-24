import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        url: String,
        field: String
    }

    async toggle(event) {
        const checkbox = event.target
        const value = checkbox.checked ? "1" : "0"

        try {
            const response = await fetch(this.urlValue, {
                method: 'PATCH',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
                    'Accept': 'application/json'
                },
                body: JSON.stringify({
                    field: this.fieldValue,
                    value: value
                })
            })

            if (!response.ok) {
                // Revert checkbox on error
                checkbox.checked = !checkbox.checked
            }
        } catch (error) {
            // Revert checkbox on error
            checkbox.checked = !checkbox.checked
        }
    }
}
