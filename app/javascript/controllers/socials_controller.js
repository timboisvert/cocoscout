import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["list", "row"]

    add(event) {
        event.preventDefault();
        const list = this.listTarget;
        const template = document.getElementById("socials-template");
        const clone = template.content.cloneNode(true);
        // Find the current max index
        let maxIndex = -1;
        list.querySelectorAll('.socials-fields-row').forEach(row => {
            const select = row.querySelector('select[name^="person[socials_attributes]"]');
            if (select) {
                const match = select.name.match(/person\[socials_attributes\]\[(\d+)\]/);
                if (match) {
                    maxIndex = Math.max(maxIndex, parseInt(match[1], 10));
                }
            }
        });
        const nextIndex = maxIndex + 1;
        // Set correct names/ids for new fields
        clone.querySelectorAll('select').forEach((el) => {
            el.name = `person[socials_attributes][${nextIndex}][platform]`;
            el.id = `person_socials_attributes_${nextIndex}_platform`;
        });
        clone.querySelectorAll('input[type="text"]').forEach((el) => {
            el.name = `person[socials_attributes][${nextIndex}][handle]`;
            el.id = `person_socials_attributes_${nextIndex}_handle`;
        });
        list.appendChild(clone);
    }

    remove(event) {
        event.preventDefault();
        const row = event.target.closest('.socials-fields-row');
        if (!row) return;
        // If persisted, set _destroy and hide; if new, remove from DOM
        if (row.dataset.socialsPersisted === "true") {
            const destroyInput = row.querySelector('input[name$="[_destroy]"]');
            if (destroyInput) {
                destroyInput.value = "1";
                row.style.display = "none";
            }
        } else {
            row.remove();
        }
    }
}
