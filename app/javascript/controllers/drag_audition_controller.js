import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["item", "dropzone"]; // Assuming 'item' is the draggable element

  connect() {
    // Optional: Initialize any libraries like SortableJS
  }

  dragStart(event) {
    // Get the draggable element itself, not a child
    const draggableElement = event.currentTarget;
    event.dataTransfer.setData("text/plain", draggableElement.dataset.id);
    event.dataTransfer.effectAllowed = "move";
    event.stopPropagation();
  }

  dragEnd(event) {
    // Optional: cleanup
  }

  dragOver(event) {
    event.preventDefault(); // Allow dropping
    event.dataTransfer.dropEffect = "move";
  }

  dragLeave(event) {
    event.preventDefault();
  }

  removeAudition(event) {
    event.preventDefault();
    event.stopPropagation();
    const auditionId = event.currentTarget.dataset.auditionId;
    const sessionId = event.currentTarget.dataset.sessionId;

    // Get the filter from the URL parameters
    const urlParams = new URLSearchParams(window.location.search);
    const filter = urlParams.get('filter') || 'to_be_scheduled';

    fetch("/manage/auditions/remove_from_session", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
      },
      body: JSON.stringify({
        audition_id: auditionId,
        audition_session_id: sessionId,
        filter: filter
      })
    })
      .then(response => {
        return response.json();
      })
      .then(data => {
        this.updatePageContent(data);
      })
      .catch(error => console.error('Error:', error));
  }

  dragStartAudition(event) {
    // Get the audition element itself
    const auditionElement = event.currentTarget;
    event.dataTransfer.setData("audition-id", auditionElement.dataset.auditionId);
    event.dataTransfer.effectAllowed = "move";
    event.stopPropagation();
  }

  dragEndAudition(event) {
    // Optional: cleanup
  }

  drop(event) {
    event.preventDefault();
    const draggedAuditionId = event.dataTransfer.getData("audition-id");
    const draggedItemId = event.dataTransfer.getData("text/plain");
    const droppedOnElement = event.target.closest("[data-drag-target='dropzone']");

    if (!droppedOnElement) return;

    // Check if this is an audition being moved between sessions or a person from the right list
    if (draggedAuditionId) {
      // Moving audition between sessions
      this.moveAuditionToSession(draggedAuditionId, droppedOnElement.dataset.id);
    } else if (draggedItemId) {
      // Dragging person from right list
      this.addPersonToSession(draggedItemId, droppedOnElement.dataset.id);
    }
  }

  moveAuditionToSession(auditionId, newSessionId) {
    // Get the filter from the URL parameters
    const urlParams = new URLSearchParams(window.location.search);
    const filter = urlParams.get('filter') || 'to_be_scheduled';

    fetch("/manage/auditions/move_to_session", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
      },
      body: JSON.stringify({
        audition_id: auditionId,
        audition_session_id: newSessionId,
        filter: filter
      })
    })
      .then(response => {
        return response.json();
      })
      .then(data => {
        this.updatePageContent(data);
      })
      .catch(error => console.error('Error:', error));
  }

  addPersonToSession(draggedItemId, droppedOnDropzoneId) {
    // Get the filter from the URL parameters
    const urlParams = new URLSearchParams(window.location.search);
    const filter = urlParams.get('filter') || 'to_be_scheduled';

    fetch("/manage/auditions/add_to_session", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
      },
      body: JSON.stringify({
        audition_request_id: draggedItemId,
        audition_session_id: droppedOnDropzoneId,
        filter: filter
      })
    })
      .then(response => {
        return response.json();
      })
      .then(data => {
        this.updatePageContent(data);
      })
      .catch(error => console.error('Error:', error));
  }

  updatePageContent(data) {
    // Update the right list (sign-ups) - use innerHTML to preserve the container
    const rightList = document.querySelector("#right_list");
    if (rightList && data.right_list_html) {
      const parser = new DOMParser();
      const doc = parser.parseFromString(data.right_list_html, 'text/html');
      const newContent = doc.querySelector('#right_list');
      if (newContent) {
        rightList.innerHTML = newContent.innerHTML;
      }
    }
    // Update the entire sessions list - use innerHTML to preserve the container
    const sessionsList = document.querySelector("#audition_sessions_list");
    if (sessionsList && data.sessions_list_html) {
      const parser = new DOMParser();
      const doc = parser.parseFromString(data.sessions_list_html, 'text/html');
      const newContent = doc.querySelector('#audition_sessions_list');
      if (newContent) {
        sessionsList.innerHTML = newContent.innerHTML;
      }
    }
  }
}