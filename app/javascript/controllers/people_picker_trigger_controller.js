import { Controller } from "@hotwired/stimulus"

// A button that opens the shared People Picker: which one (id), what the
// sheet should say (title), and what the page should know about the pick
// (context, handed back on people-picker:pick).
export default class extends Controller {
    static values = { id: { type: String, default: "people-picker" }, title: String, context: Object, params: Object }

    open(event) {
        event.preventDefault()
        window.dispatchEvent(new CustomEvent("people-picker:open", {
            detail: { id: this.idValue, title: this.titleValue, context: this.contextValue, params: this.paramsValue }
        }))
    }
}
