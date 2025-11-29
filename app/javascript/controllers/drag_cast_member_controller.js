import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["person", "group"];

  connect() {
    this.personTargets.forEach(person => {
      person.addEventListener("dragstart", this.handleDragStart);
    });
    this.groupTargets.forEach(group => {
      group.addEventListener("dragstart", this.handleDragStart);
    });
  }

  handleDragStart(event) {
    const element = event.currentTarget;
    if (element.dataset.personId) {
      event.dataTransfer.setData("assignableType", "Person");
      event.dataTransfer.setData("assignableId", element.dataset.personId);
      event.dataTransfer.setData("text/plain", element.dataset.personId); // Backward compatibility
    } else if (element.dataset.groupId) {
      event.dataTransfer.setData("assignableType", "Group");
      event.dataTransfer.setData("assignableId", element.dataset.groupId);
    }
  }
}
