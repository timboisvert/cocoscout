import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["tab", "panel", "hiddenField", "reviewCheckbox", "sendSection"]
    static values = { initialTab: { type: Number, default: 0 } }

    connect() {
        let initialTab = this.initialTabValue;

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
        // Use closest to find the button with data-index, in case click was on child element
        const tab = e.target.closest('[data-index]');
        if (!tab) return;
        const idx = parseInt(tab.dataset.index, 10);
        if (isNaN(idx)) return;

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

    checkAllReviewed() {
        // Check if all review checkboxes are checked
        if (!this.hasReviewCheckboxTarget) return;

        const allChecked = this.reviewCheckboxTargets.every(checkbox => checkbox.checked);

        // Show/hide the send section based on whether all are reviewed
        if (this.hasSendSectionTarget) {
            if (allChecked) {
                this.sendSectionTarget.classList.remove('hidden');
            } else {
                this.sendSectionTarget.classList.add('hidden');
            }
        }
    }
}
