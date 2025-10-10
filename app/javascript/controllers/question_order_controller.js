import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["item"]

    connect() {
        this.dragging = null;
    }

    startDrag(event) {
        this.dragging = event.currentTarget;
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData("text/plain", "dragging");
        this.dragging.classList.add("opacity-75");
    }

    endDrag(event) {
        if (this.dragging) {
            this.dragging.classList.remove("opacity-75");
            this.dragging = null;
        }
    }

    dragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = "move";
    }

    drop(event) {
        event.preventDefault();
        const target = event.currentTarget;
        if (this.dragging && target !== this.dragging) {
            target.parentNode.insertBefore(this.dragging, target.nextSibling);
            this.saveOrder();
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
