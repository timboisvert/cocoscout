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

        // Update the URL hash to match the initial tab
        history.replaceState(null, '', `#tab-${initialTab}`);
    }

    select(e) {
        e.preventDefault();
        const idx = parseInt(e.target.dataset.index, 10);

        // Check if we need to reload the page to clear pagination
        const urlParams = new URLSearchParams(window.location.search);
        const hasMessagesPage = urlParams.has('messages_page');

        // If we have pagination params and are switching tabs, reload without them
        if (hasMessagesPage) {
            const url = new URL(window.location.href);
            url.search = '';
            url.hash = `tab-${idx}`;
            window.location.href = url.toString();
            return;
        }

        this.show(idx);

        // Update the hidden field if it exists
        if (this.hasHiddenFieldTarget) {
            this.hiddenFieldTarget.value = idx;
        }

        // Update the URL hash
        history.replaceState(null, '', `#tab-${idx}`);
    } show(idx) {
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
