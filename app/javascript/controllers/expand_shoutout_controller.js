import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["preview", "full"]

    expand() {
        this.previewTarget.classList.add("hidden")
        this.fullTarget.classList.remove("hidden")
    }

    collapse() {
        this.previewTarget.classList.remove("hidden")
        this.fullTarget.classList.add("hidden")
    }
}
