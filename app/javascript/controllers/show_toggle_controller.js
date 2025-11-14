import { Controller } from "@hotwired/stimulus"

// Usage: data-controller="show-toggle"
//         data-show-toggle-target="content"
//         data-action="click->show-toggle#toggle"

export default class extends Controller {
    static targets = ["content", "icon", "finalizedBox"];
    static values = { initialOpen: Boolean };

    connect() {
        this.open = this.hasInitialOpenValue ? this.initialOpenValue : false;
        this.update();
        this.closeListener = (event) => {
            if (event.detail && event.detail.except === this.element) return;
            if (this.open) {
                this.open = false;
                this.update();
            }
        };
        window.addEventListener("closeAllShowToggles", this.closeListener);
    }

    disconnect() {
        window.removeEventListener("closeAllShowToggles", this.closeListener);
    }

    toggle() {
        if (!this.open) {
            window.dispatchEvent(new CustomEvent("closeAllShowToggles", { detail: { except: this.element } }));
        }
        this.open = !this.open;
        this.update();
    }

    update() {
        // Toggle finalizedBox (opposite of content)
        if (this.hasFinalizedBoxTarget) {
            this.finalizedBoxTarget.classList.toggle("hidden", this.open);
        }
        // Toggle content sections
        if (this.hasContentTarget) {
            this.contentTargets.forEach(target => {
                target.classList.toggle("hidden", !this.open);
            });
        }
        if (this.hasIconTarget) {
            this.iconTarget.innerHTML = this.open
                ? `<svg xmlns='http://www.w3.org/2000/svg' class='size-5' fill='none' viewBox='0 0 24 24' stroke='currentColor'><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M19 9l-7 7-7-7'/></svg>`
                : `<svg xmlns='http://www.w3.org/2000/svg' class='size-5' fill='none' viewBox='0 0 24 24' stroke='currentColor'><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M9 5l7 7-7 7'/></svg>`;
        }
    }
}
