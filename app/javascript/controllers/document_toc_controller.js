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

        // No headings → hide every contents rail (desktop + mobile).
        if (!headings.length) {
            this.wrapperTargets.forEach(el => el.classList.add("hidden"))
            return
        }

        // Assign stable ids once, on the shared heading nodes.
        const seen = {}
        headings.forEach(h => {
            if (h.id) return
            const base = "doc-" + (h.textContent.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "section")
            seen[base] = (seen[base] || 0) + 1
            h.id = seen[base] > 1 ? `${base}-${seen[base]}` : base
        })

        // Populate each toc nav (desktop rail + mobile collapsible).
        this.tocTargets.forEach(nav => {
            nav.replaceChildren()
            headings.forEach(h => {
                const level = h.tagName === "H1" ? 1 : h.tagName === "H2" ? 2 : 3
                const a = document.createElement("a")
                a.href = `#${h.id}`
                a.textContent = h.textContent.trim()
                a.className = "block py-1 text-gray-600 hover:text-pink-600 truncate cursor-pointer " +
                    (level === 1 ? "font-medium" : level === 2 ? "pl-3" : "pl-6 text-gray-500")
                // Scroll in JS — the document scrolls inside an overflow container,
                // so the browser/Turbo hash jump would snap the window to the top.
                a.addEventListener("click", (e) => {
                    e.preventDefault()
                    h.scrollIntoView({ behavior: "smooth", block: "start" })
                    nav.closest("details")?.removeAttribute("open")
                })
                nav.appendChild(a)
            })
        })
        this.emptyTargets.forEach(el => el.classList.add("hidden"))
    }
}
