import { Controller } from "@hotwired/stimulus"

// Search + list/grid toggle for the staffing roster. Filters staff cards
// client-side by name/email/title and switches the section containers between
// a vertical list and a responsive grid.
export default class extends Controller {
    static targets = ["search", "item", "container", "listBtn", "gridBtn", "empty"]

    static LIST_CLASSES = ["flex", "flex-col", "gap-2"]
    static GRID_CLASSES = ["grid", "grid-cols-1", "sm:grid-cols-2", "lg:grid-cols-3", "gap-2"]

    connect() {
        this.showList()
    }

    search() {
        const q = (this.hasSearchTarget ? this.searchTarget.value : "").trim().toLowerCase()
        let visible = 0
        this.itemTargets.forEach(item => {
            const hay = item.dataset.search || ""
            const match = q.length === 0 || hay.includes(q)
            item.classList.toggle("hidden", !match)
            if (match) visible++
        })
        if (this.hasEmptyTarget) {
            this.emptyTarget.classList.toggle("hidden", visible !== 0 || this.itemTargets.length === 0)
        }
    }

    showList() {
        this.applyLayout(this.constructor.LIST_CLASSES, this.constructor.GRID_CLASSES)
        this.setActive(this.listBtnTarget, this.gridBtnTarget)
    }

    showGrid() {
        this.applyLayout(this.constructor.GRID_CLASSES, this.constructor.LIST_CLASSES)
        this.setActive(this.gridBtnTarget, this.listBtnTarget)
    }

    applyLayout(addClasses, removeClasses) {
        this.containerTargets.forEach(c => {
            c.classList.remove(...removeClasses)
            c.classList.add(...addClasses)
        })
    }

    setActive(onBtn, offBtn) {
        if (onBtn) { onBtn.classList.add("bg-pink-50", "text-gray-700"); onBtn.classList.remove("bg-white", "text-gray-500") }
        if (offBtn) { offBtn.classList.add("bg-white", "text-gray-500"); offBtn.classList.remove("bg-pink-50", "text-gray-700") }
    }
}
