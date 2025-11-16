import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["list", "item", "rank", "hiddenInput"]
    static values = { questionId: Number }

    connect() {
        this.draggedItem = null
        this.touchStartY = 0
        this.touchStartItem = null
        this.dropIndicator = this.createDropIndicator()
    }

    createDropIndicator() {
        const indicator = document.createElement('div')
        indicator.className = 'h-1 bg-pink-500 rounded-full my-1 transition-all duration-150'
        indicator.style.display = 'none'
        return indicator
    }

    // Desktop drag and drop
    dragStart(event) {
        this.draggedItem = event.currentTarget
        this.draggedItem.classList.add('opacity-50')
        event.dataTransfer.effectAllowed = 'move'
        this.listTarget.appendChild(this.dropIndicator)
    }

    dragEnd(event) {
        event.currentTarget.classList.remove('opacity-50')
        this.dropIndicator.style.display = 'none'
        if (this.dropIndicator.parentNode) {
            this.dropIndicator.remove()
        }
    }

    dragOver(event) {
        event.preventDefault()
        const afterElement = this.getDragAfterElement(event.clientY)
        
        this.dropIndicator.style.display = 'block'
        
        if (afterElement == null) {
            this.listTarget.appendChild(this.draggedItem)
            this.listTarget.appendChild(this.dropIndicator)
        } else {
            this.listTarget.insertBefore(this.draggedItem, afterElement)
            this.listTarget.insertBefore(this.dropIndicator, afterElement)
        }
    }

    drop(event) {
        event.preventDefault()
        this.dropIndicator.style.display = 'none'
        if (this.dropIndicator.parentNode) {
            this.dropIndicator.remove()
        }
        this.updateRanks()
        this.updateHiddenInput()
    }

    getDragAfterElement(y) {
        const draggableElements = [...this.listTarget.querySelectorAll('[data-ranking-target="item"]:not(.opacity-50)')]

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

    // Mobile touch handlers
    touchStart(event) {
        this.touchStartY = event.touches[0].clientY
        this.touchStartItem = event.currentTarget
    }

    touchMove(event) {
        event.preventDefault()
    }

    touchEnd(event) {
        // Touch events are handled by button clicks on mobile
    }

    // Mobile arrow buttons
    moveUp(event) {
        event.preventDefault()
        const item = event.currentTarget.closest('[data-ranking-target="item"]')
        const previousItem = item.previousElementSibling

        if (previousItem) {
            this.listTarget.insertBefore(item, previousItem)
            this.updateRanks()
            this.updateHiddenInput()
            this.updateButtons()
        }
    }

    moveDown(event) {
        event.preventDefault()
        const item = event.currentTarget.closest('[data-ranking-target="item"]')
        const nextItem = item.nextElementSibling

        if (nextItem) {
            this.listTarget.insertBefore(nextItem, item)
            this.updateRanks()
            this.updateHiddenInput()
            this.updateButtons()
        }
    }

    updateRanks() {
        this.itemTargets.forEach((item, index) => {
            const rankElement = item.querySelector('[data-ranking-target="rank"]')
            if (rankElement) {
                rankElement.textContent = index + 1
            }
        })
    }

    updateHiddenInput() {
        const rankedOptions = this.itemTargets.map(item => {
            return item.dataset.optionText
        })
        this.hiddenInputTarget.value = JSON.stringify(rankedOptions)
    }

    updateButtons() {
        this.itemTargets.forEach((item, index) => {
            const upButton = item.querySelector('[data-action*="moveUp"]')
            const downButton = item.querySelector('[data-action*="moveDown"]')

            if (upButton) {
                upButton.disabled = index === 0
            }
            if (downButton) {
                downButton.disabled = index === this.itemTargets.length - 1
            }
        })
    }
}
