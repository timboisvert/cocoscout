import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["select", "panel"]

    connect() {
        // Show the initially selected panel
        this.switch()
    }

    switch() {
        const selectedValue = this.selectTarget.value

        this.panelTargets.forEach(panel => {
            const key = panel.dataset.chartSwitcherKey
            if (key === selectedValue) {
                panel.classList.remove("hidden")
            } else {
                panel.classList.add("hidden")
            }
        })
    }
}
