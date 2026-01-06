import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["item"]

    connect() {
        this.dragging = null;
        this.dropIndicator = null;
        this.touchStartY = 0;
        this.touchCurrentY = 0;
        this.touchClone = null;
    }

    startDrag(event) {
        this.dragging = event.currentTarget;
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData("text/plain", "dragging");
        this.dragging.classList.add("opacity-50");
    }

    endDrag(event) {
        if (this.dragging) {
            this.dragging.classList.remove("opacity-50");
            this.dragging = null;
        }
        this.removeDropIndicator();
    }

    // Touch event handlers for mobile
    touchStart(event) {
        this.dragging = event.currentTarget;
        const touch = event.touches[0];
        this.touchStartY = touch.clientY;

        // Create a visual clone for dragging
        this.touchClone = this.dragging.cloneNode(true);
        this.touchClone.style.cssText = 'position: fixed; pointer-events: none; opacity: 0.7; z-index: 1000; width: ' + this.dragging.offsetWidth + 'px;';
        this.touchClone.style.left = this.dragging.getBoundingClientRect().left + 'px';
        this.touchClone.style.top = touch.clientY - (this.dragging.offsetHeight / 2) + 'px';
        document.body.appendChild(this.touchClone);

        this.dragging.classList.add("opacity-50");
    }

    touchMove(event) {
        if (!this.dragging) return;

        event.preventDefault();
        const touch = event.touches[0];
        this.touchCurrentY = touch.clientY;

        // Move the clone
        if (this.touchClone) {
            this.touchClone.style.top = touch.clientY - (this.dragging.offsetHeight / 2) + 'px';
        }

        // Find the element we're hovering over
        const elementBelow = document.elementFromPoint(touch.clientX, touch.clientY);
        const targetItem = elementBelow?.closest('[data-slot-order-target="item"]');

        if (targetItem && targetItem !== this.dragging) {
            const rect = targetItem.getBoundingClientRect();
            const midpoint = rect.top + rect.height / 2;
            const insertBefore = touch.clientY < midpoint;
            this.showDropIndicator(targetItem, insertBefore);
        } else {
            this.removeDropIndicator();
        }
    }

    touchEnd(event) {
        if (!this.dragging) return;

        event.preventDefault();

        // Remove the clone
        if (this.touchClone) {
            this.touchClone.remove();
            this.touchClone = null;
        }

        // Find where to drop
        const touch = event.changedTouches[0];
        const elementBelow = document.elementFromPoint(touch.clientX, touch.clientY);
        const targetItem = elementBelow?.closest('[data-slot-order-target="item"]');

        if (targetItem && targetItem !== this.dragging) {
            const rect = targetItem.getBoundingClientRect();
            const midpoint = rect.top + rect.height / 2;
            const insertBefore = touch.clientY < midpoint;

            if (insertBefore) {
                targetItem.parentNode.insertBefore(this.dragging, targetItem);
            } else {
                targetItem.parentNode.insertBefore(this.dragging, targetItem.nextSibling);
            }
            this.saveOrder();
        }

        this.dragging.classList.remove("opacity-50");
        this.dragging = null;
        this.removeDropIndicator();
    }

    dragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = "move";

        if (!this.dragging) return;

        const target = event.currentTarget;
        if (target === this.dragging) return;

        // Calculate if we should insert before or after
        const rect = target.getBoundingClientRect();
        const midpoint = rect.top + rect.height / 2;
        const insertBefore = event.clientY < midpoint;

        this.showDropIndicator(target, insertBefore);
    }

    drop(event) {
        event.preventDefault();
        const target = event.currentTarget;

        if (this.dragging && target !== this.dragging) {
            const rect = target.getBoundingClientRect();
            const midpoint = rect.top + rect.height / 2;
            const insertBefore = event.clientY < midpoint;

            if (insertBefore) {
                target.parentNode.insertBefore(this.dragging, target);
            } else {
                target.parentNode.insertBefore(this.dragging, target.nextSibling);
            }
            this.saveOrder();
        }

        this.removeDropIndicator();
    }

    showDropIndicator(target, insertBefore) {
        this.removeDropIndicator();

        const indicator = document.createElement('div');
        indicator.className = 'drop-indicator';
        indicator.style.cssText = 'height: 3px; background-color: #ec4899; margin: -1.5px 0; border-radius: 2px; pointer-events: none;';

        if (insertBefore) {
            target.parentNode.insertBefore(indicator, target);
        } else {
            target.parentNode.insertBefore(indicator, target.nextSibling);
        }

        this.dropIndicator = indicator;
    }

    removeDropIndicator() {
        if (this.dropIndicator) {
            this.dropIndicator.remove();
            this.dropIndicator = null;
        }
    }

    saveOrder() {
        const ids = Array.from(this.itemTargets).map(el => el.dataset.id);
        const url = this.data.get("url");
        fetch(url, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
            },
            body: JSON.stringify({ ids })
        });
    }
}
