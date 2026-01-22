import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["dropZone", "auditionee", "person", "addModal"]
    static values = {
        auditionCycleId: String,
        productionId: String
    }

    connect() {
        console.log("Casting drag controller connected")
        // Close modal on escape key
        this.handleEscape = (event) => {
            if (event.key === 'Escape') this.closeAddModal();
        };
        document.addEventListener('keydown', this.handleEscape);
    }

    disconnect() {
        document.removeEventListener('keydown', this.handleEscape);
    }

    // Open the add modal for mobile
    openAddModal(event) {
        event.preventDefault();
        const button = event.currentTarget;
        const talentPoolId = button.dataset.talentPoolId;

        // Store the talent pool we're adding to
        this.currentTalentPoolId = talentPoolId;

        // Show the modal
        const modal = this.addModalTarget;
        modal.classList.remove('hidden');
        document.body.classList.add('overflow-hidden');
    }

    closeAddModal() {
        const modal = this.addModalTarget;
        if (modal) {
            modal.classList.add('hidden');
            document.body.classList.remove('overflow-hidden');
        }
        this.currentTalentPoolId = null;
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    // Add from the mobile modal
    addFromModal(event) {
        event.preventDefault();
        const button = event.currentTarget;
        const auditioneeType = button.dataset.auditioneeType;
        const auditioneeId = button.dataset.auditioneeId;
        const auditioneeName = button.dataset.auditioneeName;
        const talentPoolId = this.currentTalentPoolId;

        if (!talentPoolId || !auditioneeId) return;

        // Close modal immediately
        this.closeAddModal();

        const csrfToken = document.querySelector('meta[name=csrf-token]').content;
        this.addToCast(auditioneeType, auditioneeId, auditioneeName, talentPoolId, csrfToken, this.productionIdValue);
    }

    // When dragging from the right column (auditionees)
    dragStart(event) {
        const item = event.currentTarget
        const auditioneeType = item.dataset.auditioneeType
        const auditioneeId = item.dataset.auditioneeId
        const auditioneeName = item.dataset.auditioneeName

        event.dataTransfer.effectAllowed = "move"
        event.dataTransfer.setData("auditioneeType", auditioneeType)
        event.dataTransfer.setData("auditioneeId", auditioneeId)
        event.dataTransfer.setData("auditioneeName", auditioneeName)
        event.dataTransfer.setData("sourceType", "auditionee")

        item.classList.add("opacity-50")
    }

    // When dragging from the left column (already assigned people)
    dragStartPerson(event) {
        const item = event.currentTarget
        const auditioneeType = item.dataset.auditioneeType
        const auditioneeId = item.dataset.auditioneeId
        const auditioneeName = item.dataset.auditioneeName
        const sourceTalentPoolId = item.dataset.sourceTalentPoolId

        event.dataTransfer.effectAllowed = "move"
        event.dataTransfer.setData("auditioneeType", auditioneeType)
        event.dataTransfer.setData("auditioneeId", auditioneeId)
        event.dataTransfer.setData("auditioneeName", auditioneeName)
        event.dataTransfer.setData("sourceTalentPoolId", sourceTalentPoolId)
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

            const auditioneeType = event.dataTransfer.getData("auditioneeType")
            const auditioneeId = event.dataTransfer.getData("auditioneeId")
            const auditioneeName = event.dataTransfer.getData("auditioneeName")
            const personId = event.dataTransfer.getData("personId") // For backward compatibility with assigned people
            const personName = event.dataTransfer.getData("personName")
            const sourceType = event.dataTransfer.getData("sourceType")
            const sourceTalentPoolId = event.dataTransfer.getData("sourceTalentPoolId")
            const targetTalentPoolId = dropZone.dataset.talentPoolId

            // Don't allow dropping on the same cast
            if (sourceType === "assigned" && sourceTalentPoolId === targetTalentPoolId) {
                return
            }

            if (targetTalentPoolId) {
                if (auditioneeType && auditioneeId) {
                    this.moveToCast(auditioneeType, auditioneeId, auditioneeName, targetTalentPoolId, sourceTalentPoolId, sourceType)
                }
            }
        }
    }

    moveToCast(auditioneeType, auditioneeId, auditioneeName, targetTalentPoolId, sourceTalentPoolId, sourceType) {
        const csrfToken = document.querySelector('meta[name=csrf-token]').content
        const productionId = this.element.dataset.productionId

        // If moving from another cast, first remove from source
        if (sourceType === "assigned" && sourceTalentPoolId) {
            this.removeFromCast(auditioneeType, auditioneeId, sourceTalentPoolId, () => {
                this.addToCast(auditioneeType, auditioneeId, auditioneeName, targetTalentPoolId, csrfToken, productionId)
            })
        } else {
            // Adding from auditionee list
            this.addToCast(auditioneeType, auditioneeId, auditioneeName, targetTalentPoolId, csrfToken, productionId)
        }
    }

    addToCast(auditioneeType, auditioneeId, auditioneeName, talentPoolId, csrfToken, productionId) {
        fetch(`/manage/signups/auditions/${this.productionIdValue}/${this.auditionCycleIdValue}/add_to_cast_assignment`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": csrfToken
            },
            body: JSON.stringify({
                talent_pool_id: talentPoolId,
                auditionee_type: auditioneeType,
                auditionee_id: auditioneeId
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

    removeFromCast(auditioneeType, auditioneeId, talentPoolId, callback) {
        const csrfToken = document.querySelector('meta[name=csrf-token]').content

        fetch(`/manage/signups/auditions/${this.productionIdValue}/${this.auditionCycleIdValue}/remove_from_cast_assignment`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": csrfToken
            },
            body: JSON.stringify({
                talent_pool_id: talentPoolId,
                auditionee_type: auditioneeType,
                auditionee_id: auditioneeId
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

        if (!confirm('Are you sure you want to remove this auditionee from this talent pool?')) {
            return
        }

        const button = event.currentTarget
        const talentPoolId = button.dataset.talentPoolId
        const auditioneeType = button.dataset.auditioneeType
        const auditioneeId = button.dataset.auditioneeId
        const csrfToken = document.querySelector('meta[name=csrf-token]').content

        fetch(`/manage/signups/auditions/${this.productionIdValue}/${this.auditionCycleIdValue}/remove_from_cast_assignment`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": csrfToken
            },
            body: JSON.stringify({
                talent_pool_id: talentPoolId,
                auditionee_type: auditioneeType,
                auditionee_id: auditioneeId
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
