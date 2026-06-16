import { Controller } from "@hotwired/stimulus"

// Builds a table of contents for a rendered document by scanning its headings,
// assigning anchor ids, and linking to them. Hides the rail when there are none.
export default class extends Controller {
    static targets = ["content", "toc", "empty", "wrapper"]

    connect() {
        this.build()
    }

    build() {
        const headings = Array.from(this.contentTarget.querySelectorAll("h1, h2, h3"))
            .filter(h => h.textContent.trim().length)

        if (!headings.length) {
            this.wrapperTarget?.classList.add("hidden")
            return
        }

        const seen = {}
        this.tocTarget.replaceChildren()
        headings.forEach(h => {
            const text = h.textContent.trim()
            if (!h.id) {
                let base = "doc-" + (text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "section")
                seen[base] = (seen[base] || 0) + 1
                h.id = seen[base] > 1 ? `${base}-${seen[base]}` : base
            }
            const level = h.tagName === "H1" ? 1 : h.tagName === "H2" ? 2 : 3
            const a = document.createElement("a")
            a.href = `#${h.id}`
            a.textContent = text
            a.className = "block py-1 text-gray-600 hover:text-pink-600 truncate cursor-pointer " +
                (level === 1 ? "font-medium" : level === 2 ? "pl-3" : "pl-6 text-gray-500")
            // Scroll in JS rather than via the hash — the document scrolls inside
            // an overflow container, and letting the browser/Turbo handle the
            // anchor jumps the window back to the top.
            a.addEventListener("click", (e) => {
                e.preventDefault()
                h.scrollIntoView({ behavior: "smooth", block: "start" })
            })
            this.tocTarget.appendChild(a)
        })
        if (this.hasEmptyTarget) this.emptyTarget.classList.add("hidden")
    }
}
