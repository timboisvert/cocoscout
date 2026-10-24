import { Controller } from "@hotwired/stimulus"

// A shift's menu on the scheduling page (manage/staffing/_shift_menu): a chip
// on the week grid or a bar on a day's timeline opens it. From sm up it pops
// up at the chip; on a phone the same panel rises as a bottom sheet. Each item
// carries its own action (shift-edit#open, shift-assign#open, a confirm
// modal) and closes the menu first.
export default class extends Controller {
    connect() {
        this.onKey = (event) => { if (event.key === "Escape") this.close() }
        this.onScroll = () => { if (window.matchMedia("(min-width: 640px)").matches) this.close() }
        document.addEventListener("keydown", this.onKey)
        window.addEventListener("resize", this.onScroll)
    }

    disconnect() {
        document.removeEventListener("keydown", this.onKey)
        window.removeEventListener("resize", this.onScroll)
        window.removeEventListener("scroll", this.onScroll, true)
    }

    open(event) {
        event.preventDefault()
        event.stopPropagation()
        this.close()
        const menu = document.getElementById(event.params.id)
        if (!menu) return
        menu.classList.remove("hidden")
        this.current = menu
        const panel = menu.querySelector("[data-shift-menu-panel]")
        if (panel && window.matchMedia("(min-width: 640px)").matches) {
            this.place(panel, event.currentTarget.getBoundingClientRect())
            window.addEventListener("scroll", this.onScroll, true)
        } else if (panel) {
            panel.style.top = panel.style.left = ""
        }
    }

    // Under the chip, flipped above when there's no room, kept on screen.
    place(panel, at) {
        const margin = 8
        const rect = panel.getBoundingClientRect()
        let top = at.bottom + 4
        if (top + rect.height > window.innerHeight - margin) top = Math.max(margin, at.top - rect.height - 4)
        let left = at.left
        if (left + rect.width > window.innerWidth - margin) left = window.innerWidth - rect.width - margin
        panel.style.top = `${Math.round(top)}px`
        panel.style.left = `${Math.round(Math.max(margin, left))}px`
    }

    close() {
        window.removeEventListener("scroll", this.onScroll, true)
        if (!this.current) return
        this.current.classList.add("hidden")
        this.current = null
    }

    backdrop(event) {
        if (event.target === event.currentTarget) this.close()
    }
}
