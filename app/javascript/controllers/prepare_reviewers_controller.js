import { Controller } from "@hotwired/stimulus"

// Controls the toggle between summary view and edit form for reviewers on Prepare page
export default class extends Controller {
    static targets = ["summary", "editor"]

    toggle() {
        this.summaryTarget.classList.toggle("hidden")
        this.editorTarget.classList.toggle("hidden")
    }
}
