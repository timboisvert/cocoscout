import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["relative", "fixed"]

    toggle(event) {
        const value = event.target.value

        if (value === "relative") {
            this.relativeTarget.classList.remove("hidden")
            this.fixedTarget.classList.add("hidden")
        } else {
            this.relativeTarget.classList.add("hidden")
            this.fixedTarget.classList.remove("hidden")
        }

        // Update visual selection state on all radio options
        this.element.querySelectorAll('input[name="schedule_mode"]').forEach(radio => {
            const wrapper = radio.closest('.border-2')
            if (wrapper) {
                if (radio.checked) {
                    wrapper.classList.add('border-pink-500', 'bg-pink-50')
                    wrapper.classList.remove('border-gray-200')
                } else {
                    wrapper.classList.remove('border-pink-500', 'bg-pink-50')
                    wrapper.classList.add('border-gray-200')
                }
            }
        })
    }
}
