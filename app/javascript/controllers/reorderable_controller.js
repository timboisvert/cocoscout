import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="reorderable"
// Provides drag-and-drop reordering for list items using native HTML5 drag API
export default class extends Controller {
    static targets = ["list"]
    static values = {
        handle: { type: String, default: ".drag-handle" },
        autoSave: { type: Boolean, default: true }
    }

    connect() {
        this.injectStyles()
        this.listTargets.forEach(list => this.setupList(list))
    }

    setupList(list) {
        const items = list.querySelectorAll(":scope > [data-position]")
        items.forEach(item => this.setupItem(item))
    }

    setupItem(item) {
        const handle = item.querySelector(this.handleValue)
        if (!handle) return

        // Make the handle trigger drag on the item
        handle.addEventListener("mousedown", () => {
            item.setAttribute("draggable", "true")
        })

        handle.addEventListener("mouseup", () => {
            item.removeAttribute("draggable")
        })

        item.addEventListener("dragstart", (e) => this.dragStart(e, item))
        item.addEventListener("dragend", (e) => this.dragEnd(e, item))
        item.addEventListener("dragover", (e) => this.dragOver(e, item))
        item.addEventListener("dragenter", (e) => this.dragEnter(e, item))
        item.addEventListener("dragleave", (e) => this.dragLeave(e, item))
        item.addEventListener("drop", (e) => this.drop(e, item))
    }

    dragStart(e, item) {
        this.draggedItem = item
        item.classList.add("reorderable-dragging")
        e.dataTransfer.effectAllowed = "move"
        e.dataTransfer.setData("text/plain", item.dataset.position)

        // Delayed to allow the drag image to be captured first
        setTimeout(() => {
            item.classList.add("reorderable-ghost")
        }, 0)
    }

    dragEnd(e, item) {
        item.removeAttribute("draggable")
        item.classList.remove("reorderable-dragging", "reorderable-ghost")
        this.draggedItem = null

        // Remove all drop indicators
        document.querySelectorAll(".reorderable-drop-indicator").forEach(el => el.remove())
        document.querySelectorAll(".reorderable-drop-above, .reorderable-drop-below").forEach(el => {
            el.classList.remove("reorderable-drop-above", "reorderable-drop-below")
        })
    }

    dragOver(e, item) {
        if (!this.draggedItem || this.draggedItem === item) return
        e.preventDefault()
        e.dataTransfer.dropEffect = "move"

        // Determine if we're above or below the center of the item
        const rect = item.getBoundingClientRect()
        const midY = rect.top + rect.height / 2
        const isAbove = e.clientY < midY

        // Remove previous indicators
        item.classList.remove("reorderable-drop-above", "reorderable-drop-below")

        // Add appropriate indicator
        if (isAbove) {
            item.classList.add("reorderable-drop-above")
        } else {
            item.classList.add("reorderable-drop-below")
        }
    }

    dragEnter(e, item) {
        if (!this.draggedItem || this.draggedItem === item) return
        e.preventDefault()
    }

    dragLeave(e, item) {
        // Only remove if we're actually leaving the item (not entering a child)
        if (!item.contains(e.relatedTarget)) {
            item.classList.remove("reorderable-drop-above", "reorderable-drop-below")
        }
    }

    drop(e, item) {
        if (!this.draggedItem || this.draggedItem === item) return
        e.preventDefault()

        const rect = item.getBoundingClientRect()
        const midY = rect.top + rect.height / 2
        const insertBefore = e.clientY < midY

        const list = item.parentNode
        if (insertBefore) {
            list.insertBefore(this.draggedItem, item)
        } else {
            list.insertBefore(this.draggedItem, item.nextSibling)
        }

        // Remove drop indicators
        item.classList.remove("reorderable-drop-above", "reorderable-drop-below")

        this.updatePositions(list)

        if (this.autoSaveValue) {
            this.autoSave()
        }
    }

    injectStyles() {
        if (document.getElementById('reorderable-styles')) return

        const style = document.createElement('style')
        style.id = 'reorderable-styles'
        style.textContent = `
            .reorderable-ghost {
                opacity: 0.4;
            }
            .reorderable-dragging {
                cursor: grabbing !important;
            }
            .reorderable-drop-above {
                position: relative;
            }
            .reorderable-drop-above::before {
                content: '';
                position: absolute;
                top: -2px;
                left: 0;
                right: 0;
                height: 3px;
                background: rgb(236, 72, 153);
                border-radius: 2px;
                z-index: 10;
            }
            .reorderable-drop-below {
                position: relative;
            }
            .reorderable-drop-below::after {
                content: '';
                position: absolute;
                bottom: -2px;
                left: 0;
                right: 0;
                height: 3px;
                background: rgb(236, 72, 153);
                border-radius: 2px;
                z-index: 10;
            }
        `
        document.head.appendChild(style)
    }

    updatePositions(list) {
        const items = list.querySelectorAll(":scope > [data-position]")
        items.forEach((item, index) => {
            const input = item.querySelector("input[name*='[position]']")
            if (input) {
                input.value = index
            }
            item.dataset.position = index
        })
    }

    autoSave() {
        // Find the parent form and submit it
        const form = this.element.closest('form') || document.getElementById('performance-history-form') || document.getElementById('training-form')
        if (form) {
            form.requestSubmit()
        }
    }
}
