import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        // Auto-hide after 3 seconds
        setTimeout(() => {
            this.element.style.transition = "opacity 0.5s"
            this.element.style.opacity = "0"

            setTimeout(() => {
                this.element.remove()
            }, 500)
        }, 3000)
    }
}
