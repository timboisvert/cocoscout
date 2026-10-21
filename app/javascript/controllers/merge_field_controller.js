import { Controller } from "@hotwired/stimulus"

// "Insert field" chips above a template's editor (V1.1 plan §5): a tap
// drops {{field}} where the cursor is in the Trix editor inside this
// element, so nobody types the braces on a phone keyboard.
export default class extends Controller {
    insert(event) {
        const field = event.currentTarget.dataset.field
        const trix = this.element.querySelector("trix-editor")
        if (!field || !trix?.editor) return
        trix.editor.insertString(`{{${field}}}`)
        trix.focus()
    }
}
