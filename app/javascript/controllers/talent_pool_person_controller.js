import { Controller } from "@hotwired/stimulus"

// Controller for managing talent pool membership
// Since there's only one talent pool per production, this mainly handles remove
export default class extends Controller {
    static values = { productionId: Number, talentPoolId: Number }

    remove(event) {
        event.preventDefault();

        const memberType = event.currentTarget.dataset.memberType;
        const personId = event.currentTarget.dataset.personId;
        const productionId = this.productionIdValue;

        // Navigate to confirmation page
        // Routes are now collection routes (no talent pool id in URL)
        const endpoint = memberType === "Person" ? "confirm-remove-person" : "confirm-remove-group";
        window.location.href = `/manage/casting/${productionId}/talent-pools/${endpoint}/${personId}`;
    }
}
