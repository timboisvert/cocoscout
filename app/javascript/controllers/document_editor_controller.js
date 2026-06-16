import { Controller } from "@hotwired/stimulus"

// Register extra heading levels on the globally-loaded Trix (set up by
// application.js's `import "trix"`). Importing "trix" directly here can fail
// under importmap and take the whole controller down with it, so use window.Trix.
// Run on `trix-before-initialize` (fired before each editor parses its content)
// so stored H2/H3 always round-trips — config must exist before parsing.
function configureHeadingLevels() {
    const Trix = window.Trix
    if (Trix?.config && !Trix.config.blockAttributes.heading2) {
        Trix.config.blockAttributes.heading2 = { tagName: "h2", terminal: true, breakOnReturn: true, group: false }
        Trix.config.blockAttributes.heading3 = { tagName: "h3", terminal: true, breakOnReturn: true, group: false }
    }
}
document.addEventListener("trix-before-initialize", configureHeadingLevels)

// Full-page document editor: relocates the Trix toolbar under the title, swaps
// the single heading button for H1/H2/H3, and keeps a live table of contents in
// the left rail.
export default class extends Controller {
    static targets = ["editor", "toolbarSlot", "toc", "tocEmpty"]

    connect() {
        configureHeadingLevels()
        this.editorEl = this.hasEditorTarget ? this.editorTarget : this.element.querySelector("trix-editor")
        if (!this.editorEl) return
        this._onChange = () => this.buildToc()

        if (this.editorEl.editor) {
            this.setup()
        } else {
            this._onInit = () => this.setup()
            this.editorEl.addEventListener("trix-initialize", this._onInit, { once: true })
        }
    }

    disconnect() {
        this.editorEl?.removeEventListener("trix-change", this._onChange)
    }

    setup() {
        this.relocateToolbar()
        this.addHeadingButtons()
        this.editorEl.addEventListener("trix-change", this._onChange)
        this.buildToc()
    }

    relocateToolbar() {
        this.toolbar = this.editorEl.toolbarElement
        if (this.toolbar && this.hasToolbarSlotTarget) this.toolbarSlotTarget.appendChild(this.toolbar)
    }

    // Replace Trix's lone heading button with H1 / H2 / H3 (mutually exclusive).
    addHeadingButtons() {
        const toolbar = this.toolbar
        if (!toolbar || toolbar.dataset.headingsReady) return
        toolbar.dataset.headingsReady = "true"

        const def = toolbar.querySelector("[data-trix-attribute='heading1']")
        const group = def ? def.closest(".trix-button-group") : toolbar.querySelector(".trix-button-group")
        if (def) def.remove()
        if (!group) return

        const anchor = group.firstChild
        this.headingButtons = [["heading1", "H1"], ["heading2", "H2"], ["heading3", "H3"]].map(([attr, label]) => {
            const b = document.createElement("button")
            b.type = "button"
            b.textContent = label
            b.className = "trix-button trix-button--heading"
            b.dataset.headingLevel = attr
            b.addEventListener("mousedown", (e) => { e.preventDefault(); this.toggleHeading(attr) })
            group.insertBefore(b, anchor)
            return b
        })

        this.editorEl.addEventListener("trix-selection-change", () => this.refreshHeadingState())
        this.refreshHeadingState()
    }

    toggleHeading(attr) {
        const ed = this.editorEl.editor
        if (!ed) return
        const active = ed.attributeIsActive(attr)
        ;["heading1", "heading2", "heading3"].forEach(a => { if (ed.attributeIsActive(a)) ed.deactivateAttribute(a) })
        if (!active) ed.activateAttribute(attr)
        this.refreshHeadingState()
    }

    refreshHeadingState() {
        const ed = this.editorEl.editor
        if (!ed || !this.headingButtons) return
        this.headingButtons.forEach(b => b.classList.toggle("trix-active", ed.attributeIsActive(b.dataset.headingLevel)))
    }

    // Rebuild the live table of contents from the editor's headings.
    buildToc() {
        if (!this.hasTocTarget) return
        const headings = Array.from(this.editorEl.querySelectorAll("h1, h2, h3"))
            .filter(h => h.textContent.trim().length)

        this.tocTarget.replaceChildren()
        if (this.hasTocEmptyTarget) this.tocEmptyTarget.classList.toggle("hidden", headings.length > 0)
        if (!headings.length) return

        headings.forEach(h => {
            const level = h.tagName === "H1" ? 1 : h.tagName === "H2" ? 2 : 3
            const a = document.createElement("a")
            a.href = "#"
            a.textContent = h.textContent.trim()
            a.className = "block py-1 text-gray-600 hover:text-pink-600 truncate cursor-pointer " +
                (level === 1 ? "font-medium" : level === 2 ? "pl-3" : "pl-6 text-gray-500")
            a.addEventListener("click", (e) => { e.preventDefault(); h.scrollIntoView({ behavior: "smooth", block: "center" }) })
            this.tocTarget.appendChild(a)
        })
    }
}
