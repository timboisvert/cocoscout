import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["tab", "panel", "hiddenField", "reviewCheckbox", "sendSection", "menu", "sectionLabel", "sectionItem"]
    // plain: tabs drawn the settings-page way (no gray fill on the inactive
    // ones), as shared/settings_layout draws its strip.
    // On a phone the strip gives way to shared/section_picker: a row naming
    // the section showing (sectionLabel) and a sheet of them all
    // (sectionItem), both kept in step here.
    // url: false keeps the address out of it (tabs in a modal, where ?tab=
    // and #tab- belong to the page under it).
    // Each switch dispatches tabs:change with { index }, for a controller
    // that changes more than the panels (a modal's footer buttons).
    static values = { initialTab: { type: Number, default: 0 }, selectKey: String, plain: Boolean, url: { type: Boolean, default: true } }

    connect() {
        let initialTab = this.initialTabValue;

        // First check if there's a selectKey value - find tab with matching data-key
        // Skip if selectKey is empty, "0", or not set
        const selectKey = this.hasSelectKeyValue ? String(this.selectKeyValue) : "";
        if (selectKey && selectKey !== "0") {
            const matchingTab = this.tabTargets.find(tab => String(tab.dataset.key) === selectKey);
            if (matchingTab) {
                const matchingIndex = parseInt(matchingTab.dataset.index, 10);
                if (!isNaN(matchingIndex)) {
                    initialTab = matchingIndex;
                }
            }
        }
        // Then check if there's a tab in the URL query params
        else if (this.urlValue) {
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
                        requested = true;
                    }
                }
            }
        }

        this.show(initialTab);

        // Update the URL hash to match the initial tab (but not for modals).
        // ?tab= is a one-shot instruction — a controller redirect saying "come
        // back to this tab", which a #hash can't carry because fetch drops the
        // fragment off a redirect's Location. Consume it here so the hash is the
        // only thing tracking the tab from now on, and a later reload doesn't
        // yank you back to the redirect's tab.
        if (!selectKey && this.urlValue) {
            const url = new URL(window.location.href);
            url.searchParams.delete('tab');
            url.hash = `tab-${initialTab}`;
            history.replaceState(null, '', url.toString());
        }
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
        if (hasMessagesPage && this.urlValue) {
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
        if (this.urlValue) history.replaceState(null, '', `#tab-${idx}`);
    }

    // Mobile dropdown alternative to the tab strip (change event).
    selectMenu(e) {
        const idx = parseInt(e.target.value, 10);
        if (isNaN(idx)) return;
        this.show(idx);
        if (this.hasHiddenFieldTarget) this.hiddenFieldTarget.value = idx;
        if (this.urlValue) history.replaceState(null, '', `#tab-${idx}`);
    }

    show(idx) {
        // Keep the mobile dropdown in sync when tabs change via any path.
        if (this.hasMenuTarget) this.menuTarget.value = String(idx);
        const fill = this.plainValue ? [] : ["bg-white"]
        const unfilled = this.plainValue ? [] : ["bg-gray-50"]
        this.tabTargets.forEach((tab, i) => {
            if (i === idx) {
                tab.classList.add("border-pink-500", "text-pink-600", ...fill);
                tab.classList.remove("border-transparent", "text-gray-500", ...unfilled);
            } else {
                tab.classList.remove("border-pink-500", "text-pink-600", ...fill);
                tab.classList.add("border-transparent", "text-gray-500", ...unfilled);
            }
        });
        this.panelTargets.forEach((panel, i) => {
            panel.classList.toggle("hidden", i !== idx);
        });
        // The phone's picker: check the section showing, and name it on the row.
        this.sectionItemTargets.forEach(item => {
            const active = parseInt(item.dataset.index, 10) === idx;
            item.classList.toggle("text-pink-600", active);
            item.classList.toggle("font-medium", active);
            item.classList.toggle("text-gray-800", !active);
            item.querySelector("[data-section-check]")?.classList.toggle("hidden", !active);
            if (active) item.setAttribute("aria-current", "true"); else item.removeAttribute("aria-current");
            const name = item.querySelector("[data-section-name]");
            if (active && name && this.hasSectionLabelTarget) this.sectionLabelTarget.innerHTML = name.innerHTML;
        });
        this.dispatch("change", { detail: { index: idx } });
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
