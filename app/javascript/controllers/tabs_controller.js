import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["tab", "panel", "hiddenField"]

    connect() {
        let initialTab = 0;

        // First check if there's a tab in the URL query params
        const urlParams = new URLSearchParams(window.location.search);
        const tabParam = urlParams.get('tab');

        if (tabParam) {
            const tabIndex = parseInt(tabParam, 10);
            if (!isNaN(tabIndex) && tabIndex >= 0 && tabIndex < this.tabTargets.length) {
                initialTab = tabIndex;
            }
        }
        // Fallback to URL hash
        else {
            const hash = window.location.hash;
            if (hash && hash.startsWith('#tab-')) {
                const tabIndex = parseInt(hash.replace('#tab-', ''), 10);
                if (!isNaN(tabIndex) && tabIndex >= 0 && tabIndex < this.tabTargets.length) {
                    initialTab = tabIndex;
                }
            }
        }

        this.show(initialTab);
    }

    select(e) {
        e.preventDefault();
        const idx = parseInt(e.target.dataset.index, 10);
        this.show(idx);

        // Update the hidden field if it exists
        if (this.hasHiddenFieldTarget) {
            this.hiddenFieldTarget.value = idx;
        }

        // Update the URL hash without triggering a page scroll
        history.replaceState(null, '', `#tab-${idx}`);
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

        // Hide/show the form buttons based on active tab
        // This is a hack just for the edit call to audition form
        const buttonsDiv = document.getElementById('call-to-audition-form-buttons');
        if (buttonsDiv) {
            if (idx === 2) {
                buttonsDiv.style.display = "none";
            } else {
                buttonsDiv.style.display = "";
            }
        }
    }
}
