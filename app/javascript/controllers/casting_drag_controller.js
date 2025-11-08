import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["item", "castMembers"]

    dragStart(event) {
        const item = event.currentTarget
        const personId = item.dataset.personId
        const personName = item.dataset.personName

        event.dataTransfer.effectAllowed = "move"
        event.dataTransfer.setData("personId", personId)
        event.dataTransfer.setData("personName", personName)
        event.dataTransfer.setData("sourceType", item.dataset.dragDropTarget)

        item.classList.add("opacity-50")
    }

    dragEnd(event) {
        event.currentTarget.classList.remove("opacity-50")
    }

    dragOver(event) {
        event.preventDefault()
        event.dataTransfer.dropEffect = "move"

        // Highlight drop zones
        const dropZone = event.currentTarget.closest("[data-drag-drop-type]")
        if (dropZone) {
            dropZone.classList.add("bg-pink-100")
        }
    }

    dragLeave(event) {
        const dropZone = event.currentTarget.closest("[data-drag-drop-type]")
        if (dropZone && !dropZone.contains(event.relatedTarget)) {
            dropZone.classList.remove("bg-pink-100")
        }
    }

    drop(event) {
        event.preventDefault()
        const dropZone = event.currentTarget.closest("[data-drag-drop-type]")

        if (dropZone) {
            dropZone.classList.remove("bg-pink-100")

            const personId = event.dataTransfer.getData("personId")
            const castId = dropZone.dataset.castId

            if (castId && personId) {
                this.addPersonToCast(personId, castId)
            }
        }
    }

    addPersonToCast(personId, castId) {
        const csrfToken = document.querySelector('meta[name=csrf-token]').content
        const productionId = this.element.dataset.productionId || this.getProductionIdFromUrl()

        fetch(`/manage/productions/${productionId}/casts/${castId}/add_person?person_id=${personId}`, {
            method: "POST",
            headers: {
                "X-CSRF-Token": csrfToken
            }
        })
            .then(response => {
                // Reload the page to show updated cast
                window.location.reload()
            })
            .catch(error => console.error('Error:', error))
    }

    getProductionIdFromUrl() {
        const match = window.location.pathname.match(/\/manage\/productions\/(\d+)/)
        return match ? match[1] : null
    }
}
