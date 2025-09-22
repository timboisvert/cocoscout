import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["item", "dropzone"]; // Assuming 'item' is the draggable element

  connect() {
    // Optional: Initialize any libraries like SortableJS
  }

  dragStart(event) {
    event.dataTransfer.setData("text/plain", event.target.dataset.id); // Store item ID
    event.dataTransfer.effectAllowed = "move";
  }

  dragOver(event) {
    event.preventDefault(); // Allow dropping
    event.dataTransfer.dropEffect = "move";
  }

  dragLeave(event) {
    // Optional: Remove visual feedback
  }

  drop(event) {
    event.preventDefault();
    const draggedItemId = event.dataTransfer.getData("text/plain");
    const droppedOnElement = event.target.closest("[data-drag-target='dropzone']");

    if (droppedOnElement) {
      const droppedOnDropzoneId = droppedOnElement.dataset.id;
      // Send AJAX request to create audition and add to session
      fetch("/manage/auditions/add_to_session", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
        },
        body: JSON.stringify({
          audition_request_id: draggedItemId,
          audition_session_id: droppedOnDropzoneId
        })
      })
        .then(response => response.json())
        .then(data => {
          // Update the left list
          const leftList = document.querySelector("#left_panel");
          if (leftList && data.left_list_html) {
            leftList.outerHTML = data.left_list_html;
          }
          // Update the dropzone
          if (droppedOnElement && data.dropzone_html) {
            droppedOnElement.outerHTML = data.dropzone_html;
          }
        });
    }
  }

  updateOrder(draggedId, droppedOnId) {
    // Implement AJAX request to update the order on the server
    // e.g., using fetch or @rails/request.js
  }

  removeAudition(event) {
    event.preventDefault();
    event.stopPropagation();
    const auditionId = event.currentTarget.dataset.auditionId;
    const sessionId = event.currentTarget.dataset.sessionId;
    fetch("/manage/auditions/remove_from_session", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
      },
      body: JSON.stringify({
        audition_id: auditionId,
        audition_session_id: sessionId
      })
    })
      .then(response => response.json())
      .then(data => {
        // Update the left list
        const leftList = document.querySelector("#left_panel");
        if (leftList && data.left_list_html) {
          leftList.outerHTML = data.left_list_html;
        }
        // Update the dropzone
        const dropzone = document.querySelector(`[data-drag-target='dropzone'][data-id='${sessionId}']`);
        if (dropzone && data.dropzone_html) {
          dropzone.outerHTML = data.dropzone_html;
        }
      });
  }
}