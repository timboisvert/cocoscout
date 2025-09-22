import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { productionId: Number, castId: Number }

    add(event) {
        event.preventDefault();
        const personId = event.currentTarget.dataset.personId;
        const productionId = this.productionIdValue;
        const castId = this.castIdValue;
        fetch(`/manage/productions/${productionId}/casts/${castId}/add_person`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify({ person_id: personId })
        })
            .then(r => r.text())
            .then(html => {
                // Replace the cast members list with the new HTML
                const castList = document.getElementById(`cast-members-list-${castId}`);
                if (castList) castList.innerHTML = html;
            });
    }

    remove(event) {
        event.preventDefault();
        const personId = event.currentTarget.dataset.personId;
        const productionId = this.productionIdValue;
        const castId = this.castIdValue;
        fetch(`/manage/productions/${productionId}/casts/${castId}/remove_person`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
            },
            body: JSON.stringify({ person_id: personId })
        })
            .then(r => r.text())
            .then(html => {
                // Replace the cast members list with the new HTML
                const castList = document.getElementById(`cast-members-list-${castId}`);
                if (castList) castList.innerHTML = html;
            });
    }

}
