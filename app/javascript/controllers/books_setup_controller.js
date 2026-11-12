import { Controller } from "@hotwired/stimulus"

// Set up your categories (Books): the answers on the left decide which
// built-in categories are recommended on the right. Each answer carries
// the flags it stands for (data-flags); each category the flags it is for
// (data-for, empty = everyone). Changing an answer re-ticks the categories
// nobody has touched by hand; a category ticked or unticked by hand stays
// that way. "Another" adds a row for a category of the organization's own.
export default class extends Controller {
    static targets = ["answer", "category", "badge", "customRows"]

    connect() {
        // A box that already differs from its recommendation was chosen on purpose.
        this.categoryTargets.forEach(box => {
            if (box.checked !== (box.dataset.recommended === "true")) box.dataset.touched = "1"
        })
    }

    flags() {
        const flags = new Set()
        this.answerTargets.forEach(input => {
            if (!input.checked) return
            (input.dataset.flags || "").split(" ").filter(Boolean).forEach(f => flags.add(f))
        })
        return flags
    }

    recommend() {
        const flags = this.flags()
        this.categoryTargets.forEach(box => {
            const wanted = (box.dataset.for || "").split(" ").filter(Boolean)
            const recommended = wanted.length === 0 || wanted.some(f => flags.has(f))
            box.dataset.recommended = recommended ? "true" : "false"
            if (!box.dataset.touched) box.checked = recommended
            const badge = this.badgeTargets.find(b => b.dataset.for === box.value)
            if (badge) badge.classList.toggle("hidden", !recommended)
        })
    }

    touch(event) {
        event.target.dataset.touched = "1"
    }

    another(event) {
        const rows = event.target.closest("[data-books-setup-target='custom']").querySelector("[data-books-setup-target='customRows']")
        const row = rows.lastElementChild.cloneNode(true)
        row.querySelectorAll("input").forEach(input => { input.value = "" })
        rows.appendChild(row)
        row.querySelector("input").focus()
    }
}
