import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["dropZone", "auditionee", "person"]
    static values = { 
        callToAuditionId: String,
        productionId: String
    }

    connect() {
        console.log("Casting drag controller connected")
    }

    // When dragging from the right column (auditionees)
    dragStart(event) {
        const item = event.currentTarget
        const personId = item.dataset.personId
        const personName = item.dataset.personName

        event.dataTransfer.effectAllowed = "move"
        event.dataTransfer.setData("personId", personId)
        event.dataTransfer.setData("personName", personName)
        event.dataTransfer.setData("sourceType", "auditionee")

        item.classList.add("opacity-50")
    }

    // When dragging from the left column (already assigned people)
    dragStartPerson(event) {
        const item = event.currentTarget
        const personId = item.dataset.personId
        const personName = item.dataset.personName
        const sourceCastId = item.dataset.sourceCastId

        event.dataTransfer.effectAllowed = "move"
        event.dataTransfer.setData("personId", personId)
        event.dataTransfer.setData("personName", personName)
        event.dataTransfer.setData("sourceCastId", sourceCastId)
        event.dataTransfer.setData("sourceType", "assigned")

        item.classList.add("opacity-50")
    }

    dragEnd(event) {
        event.currentTarget.classList.remove("opacity-50")
    }

    allowDrop(event) {
        event.preventDefault()
        event.dataTransfer.dropEffect = "move"

        const dropZone = event.target.closest("[data-casting-drag-target='dropZone']")
        if (dropZone) {
            dropZone.classList.add("bg-pink-50", "border-pink-400")
        }
    }

    dragLeave(event) {
        const dropZone = event.target.closest("[data-casting-drag-target='dropZone']")
        if (dropZone && !dropZone.contains(event.relatedTarget)) {
            dropZone.classList.remove("bg-pink-50", "border-pink-400")
        }
    }

    drop(event) {
        event.preventDefault()
        const dropZone = event.target.closest("[data-casting-drag-target='dropZone']")

        if (dropZone) {
            dropZone.classList.remove("bg-pink-50", "border-pink-400")

            const personId = event.dataTransfer.getData("personId")
            const personName = event.dataTransfer.getData("personName")
            const sourceType = event.dataTransfer.getData("sourceType")
            const sourceCastId = event.dataTransfer.getData("sourceCastId")
            const targetCastId = dropZone.dataset.castId

            // Don't allow dropping on the same cast
            if (sourceType === "assigned" && sourceCastId === targetCastId) {
                return
            }

            if (targetCastId && personId) {
                this.moveToCast(personId, personName, targetCastId, sourceCastId, sourceType)
            }
        }
    }

    moveToCast(personId, personName, targetCastId, sourceCastId, sourceType) {
        const csrfToken = document.querySelector('meta[name=csrf-token]').content
        const productionId = this.element.dataset.productionId

        // If moving from another cast, first remove from source
        if (sourceType === "assigned" && sourceCastId) {
            this.removeFromCast(personId, sourceCastId, () => {
                this.addToCast(personId, personName, targetCastId, csrfToken, productionId)
            })
        } else {
            // Adding from auditionee list
            this.addToCast(personId, personName, targetCastId, csrfToken, productionId)
        }
    }

    addToCast(personId, personName, castId, csrfToken, productionId) {
        fetch(`/manage/productions/${this.productionIdValue}/call_to_auditions/${this.callToAuditionIdValue}/add_to_cast_assignment`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": csrfToken
            },
            body: JSON.stringify({
                cast_id: castId,
                person_id: personId
            })
        })
            .then(response => {
                if (response.ok) {
                    // Reload the page to show the updated cast
                    window.location.reload()
                } else {
                    console.error('Error response:', response.status)
                }
            })
            .catch(error => console.error('Error:', error))
    }

    removeFromCast(personId, castId, callback) {
        const csrfToken = document.querySelector('meta[name=csrf-token]').content

        fetch(`/manage/productions/${this.productionIdValue}/call_to_auditions/${this.callToAuditionIdValue}/remove_from_cast_assignment`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": csrfToken
            },
            body: JSON.stringify({
                cast_id: castId,
                person_id: personId
            })
        })
            .then(response => {
                if (response.ok && callback) {
                    callback()
                } else if (!response.ok) {
                    console.error('Error response:', response.status)
                }
            })
            .catch(error => console.error('Error:', error))
    }

    removePerson(event) {
        event.preventDefault()
        const button = event.currentTarget
        const castId = button.dataset.castId
        const personId = button.dataset.personId
        const csrfToken = document.querySelector('meta[name=csrf-token]').content

        fetch(`/manage/productions/${this.productionIdValue}/call_to_auditions/${this.callToAuditionIdValue}/remove_from_cast_assignment`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": csrfToken
            },
            body: JSON.stringify({
                cast_id: castId,
                person_id: personId
            })
        })
            .then(response => {
                if (response.ok) {
                    // Reload the page to show the updated cast
                    window.location.reload()
                } else {
                    console.error('Error response:', response.status)
                }
            })
            .catch(error => console.error('Error:', error))
    }
}
