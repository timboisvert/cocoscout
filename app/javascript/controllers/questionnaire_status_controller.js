import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["toggle", "archiveButton", "statusLabel"]

    toggleStatus(event) {
        const checkbox = event.target
        const questionnaireId = this.element.dataset.questionnaireId
        const productionId = this.element.dataset.productionId
        const accepting = checkbox.checked

        fetch(`/manage/casting/${productionId}/questionnaires/${questionnaireId}`, {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
                'Accept': 'application/json'
            },
            body: JSON.stringify({
                questionnaire: {
                    accepting_responses: accepting
                }
            })
        })
            .then(response => {
                if (!response.ok) {
                    throw new Error('Network response was not ok')
                }
                return response.json()
            })
            .then(data => {
                // Update status label
                if (this.hasStatusLabelTarget) {
                    this.statusLabelTarget.textContent = accepting ? 'Accepting Responses' : 'Not Accepting Responses'
                }

                // Toggle archive button visibility
                if (this.hasArchiveButtonTarget) {
                    if (accepting) {
                        this.archiveButtonTarget.classList.add('hidden')
                    } else {
                        this.archiveButtonTarget.classList.remove('hidden')
                    }
                }
            })
            .catch(error => {
                console.error('Error:', error)
                // Revert checkbox on error
                checkbox.checked = !accepting
                alert('Failed to update status. Please try again.')
            })
    }
}
