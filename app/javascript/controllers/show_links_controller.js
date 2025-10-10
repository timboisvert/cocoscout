import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["list", "template"]

    add(e) {
        e.preventDefault();
        const time = new Date().getTime();
        const content = this.templateTarget.innerHTML.replace(/new_show_links/g, time);
        this.listTarget.insertAdjacentHTML("beforeend", content);
    }

    remove(e) {
        e.preventDefault();
        const field = e.target.closest(".show-links-fields-row");
        const destroyFlag = field.querySelector(".destroy-flag");
        if (destroyFlag) {
            destroyFlag.value = "1";
        }
        field.style.display = "none";
    }
}
