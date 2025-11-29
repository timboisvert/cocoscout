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
            const select = row.querySelector('select[name*="[socials_attributes]"]');
            if (select) {
                const match = select.name.match(/\[socials_attributes\]\[(\d+)\]/);
                if (match) {
                    maxIndex = Math.max(maxIndex, parseInt(match[1], 10));
                }
            }
        });
        const nextIndex = maxIndex + 1;

        // Determine the correct base name by checking existing fields, or from template data attribute
        let baseName = 'audition_request[person][socials_attributes]';
        let baseId = 'audition_request_person_socials_attributes';
        const existingSelect = list.querySelector('select[name*="[socials_attributes]"]');
        if (existingSelect) {
            const nameMatch = existingSelect.name.match(/(.*)\[socials_attributes\]/);
            if (nameMatch) {
                baseName = nameMatch[1] + '[socials_attributes]';
                baseId = nameMatch[1].replace(/\[/g, '_').replace(/\]/g, '') + '_socials_attributes';
            }
        } else if (template.dataset.entityName) {
            // No existing fields, use the entity name from template
            const entityName = template.dataset.entityName;
            baseName = `${entityName}[socials_attributes]`;
            baseId = `${entityName}_socials_attributes`;
        }

        // Set correct names/ids for new fields
        clone.querySelectorAll('select').forEach((el) => {
            el.name = `${baseName}[${nextIndex}][platform]`;
            el.id = `${baseId}_${nextIndex}_platform`;
            // Add auto-save data-action
            el.setAttribute('data-action', 'change->profile-auto-save#save');
        });
        clone.querySelectorAll('input[type="text"]').forEach((el) => {
            el.name = `${baseName}[${nextIndex}][handle]`;
            el.id = `${baseId}_${nextIndex}_handle`;
            // Add auto-save data-action
            el.setAttribute('data-action', 'blur->profile-auto-save#save');
        });
        list.appendChild(clone);

        // Focus the new handle input
        const newRow = list.lastElementChild;
        const handleInput = newRow.querySelector('input[type="text"]');
        if (handleInput) {
            handleInput.focus();
        }
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
                // Hide the row but keep it in the DOM so the form submits the _destroy field
                row.style.visibility = "hidden";
                row.style.height = "0";
                row.style.overflow = "hidden";
                row.style.margin = "0";

                // Trigger auto-save by dispatching a change event on the destroy input
                destroyInput.dispatchEvent(new Event('change', { bubbles: true }));
            }
        } else {
            row.remove();
        }
    }
}
