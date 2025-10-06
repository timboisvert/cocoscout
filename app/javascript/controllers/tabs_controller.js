import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["tab", "panel"]

    connect() {
        this.show(0);
    }

    select(e) {
        e.preventDefault();
        const idx = parseInt(e.target.dataset.index, 10);
        this.show(idx);
    }

    show(idx) {
        this.tabTargets.forEach((tab, i) => {
            if (i === idx) {
                tab.classList.add("border-pink-500", "text-pink-600", "bg-white");
                tab.classList.remove("border-transparent", "text-gray-500", "bg-gray-50");
            } else {
                tab.classList.remove("border-pink-500", "text-pink-600", "bg-white");
                tab.classList.add("border-transparent", "text-gray-500", "bg-gray-50");
            }
        });
        this.panelTargets.forEach((panel, i) => {
            panel.classList.toggle("hidden", i !== idx);
        });
    }
}
