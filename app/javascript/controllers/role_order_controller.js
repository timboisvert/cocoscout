import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["item"]
    static values = { url: String }

    connect() {
        this.draggedElement = null
        this.dropIndicator = null
        this.touchStartY = 0
        this.touchCurrentY = 0
    }

    startDrag(event) {
        this.draggedElement = event.target.closest('[data-role-order-target="item"]')
        event.dataTransfer.effectAllowed = "move"
        event.dataTransfer.setData("text/html", this.draggedElement.innerHTML)
        this.draggedElement.classList.add("opacity-50")
    }

    endDrag(event) {
        this.draggedElement.classList.remove("opacity-50")
        this.removeDropIndicator()
        this.saveOrder()
    }

    dragOver(event) {
        if (event.preventDefault) {
            event.preventDefault()
        }
        event.dataTransfer.dropEffect = "move"

        const afterElement = this.getDragAfterElement(event.clientY)
        const draggable = this.draggedElement

        // Show drop indicator
        if (afterElement == null) {
            this.showDropIndicator(this.itemTargets[this.itemTargets.length - 1], false)
        } else {
            this.showDropIndicator(afterElement, true)
        }

        if (afterElement == null) {
            this.element.appendChild(draggable)
        } else {
            this.element.insertBefore(draggable, afterElement)
        }

        return false
    }

    drop(event) {
        if (event.stopPropagation) {
            event.stopPropagation()
        }
        this.removeDropIndicator()
        return false
    }

    getDragAfterElement(y) {
        const draggableElements = [...this.itemTargets].filter(item => item !== this.draggedElement)

        return draggableElements.reduce((closest, child) => {
            const box = child.getBoundingClientRect()
            const offset = y - box.top - box.height / 2

            if (offset < 0 && offset > closest.offset) {
                return { offset: offset, element: child }
            } else {
                return closest
            }
        }, { offset: Number.NEGATIVE_INFINITY }).element
    }

    // Touch events for mobile
    touchStart(event) {
        this.draggedElement = event.target.closest('[data-role-order-target="item"]')
        this.touchStartY = event.touches[0].clientY
        this.draggedElement.classList.add("opacity-50")
    }

    touchMove(event) {
        event.preventDefault()
        this.touchCurrentY = event.touches[0].clientY

        const afterElement = this.getDragAfterElement(this.touchCurrentY)
        const draggable = this.draggedElement

        // Show drop indicator
        if (afterElement == null) {
            this.showDropIndicator(this.itemTargets[this.itemTargets.length - 1], false)
        } else {
            this.showDropIndicator(afterElement, true)
        }

        if (afterElement == null) {
            this.element.appendChild(draggable)
        } else {
            this.element.insertBefore(draggable, afterElement)
        }
    }

    touchEnd(event) {
        this.draggedElement.classList.remove("opacity-50")
        this.removeDropIndicator()
        this.saveOrder()
    }

    saveOrder() {
        const roleIds = this.itemTargets.map(item => item.dataset.id)

        fetch(this.urlValue, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
            },
            body: JSON.stringify({ role_ids: roleIds })
        })
    }

    showDropIndicator(target, insertBefore) {
        this.removeDropIndicator()

        const indicator = document.createElement('div')
        indicator.className = 'drop-indicator'
        indicator.style.cssText = 'height: 3px; background-color: #ec4899; margin: -1.5px 0; border-radius: 2px; pointer-events: none;'

        if (insertBefore) {
            target.parentNode.insertBefore(indicator, target)
        } else {
            target.parentNode.insertBefore(indicator, target.nextSibling)
        }

        this.dropIndicator = indicator
    }

    removeDropIndicator() {
        if (this.dropIndicator) {
            this.dropIndicator.remove()
            this.dropIndicator = null
        }
    }
}
