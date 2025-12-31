import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["item", "dropzone", "addModal"]; // Assuming 'item' is the draggable element

  connect() {
    // Close modal on escape key
    this.handleEscape = (event) => {
      if (event.key === 'Escape') this.closeAddModal();
    };
    document.addEventListener('keydown', this.handleEscape);
  }

  disconnect() {
    document.removeEventListener('keydown', this.handleEscape);
  }

  // Open the add modal for mobile
  openAddModal(event) {
    event.preventDefault();
    const button = event.currentTarget;
    const sessionId = button.dataset.sessionId;
    const sessionDate = button.dataset.sessionDate;

    // Store the session we're adding to
    this.currentAddSessionId = sessionId;

    // Update modal title
    const modal = this.addModalTarget;
    const titleEl = modal.querySelector('[data-modal-title]');
    if (titleEl) {
      titleEl.textContent = `Add to ${sessionDate}`;
    }

    // Show the modal
    modal.classList.remove('hidden');
    document.body.classList.add('overflow-hidden');
  }

  closeAddModal() {
    const modal = this.addModalTarget;
    if (modal) {
      modal.classList.add('hidden');
      document.body.classList.remove('overflow-hidden');
    }
    this.currentAddSessionId = null;
  }

  stopPropagation(event) {
    event.stopPropagation();
  }

  // Add from the mobile modal
  addFromModal(event) {
    event.preventDefault();
    const button = event.currentTarget;
    const auditionRequestId = button.dataset.auditionRequestId;
    const sessionId = this.currentAddSessionId;

    if (!sessionId || !auditionRequestId) return;

    // Close modal immediately
    this.closeAddModal();

    fetch("/manage/auditions/add_to_session", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
      },
      body: JSON.stringify({
        audition_request_id: auditionRequestId,
        audition_session_id: sessionId
      })
    })
      .then(response => response.json())
      .then(data => {
        this.updatePageContent(data);
      })
      .catch(error => console.error('Error:', error));
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
    // Add visual feedback
    event.currentTarget.classList.add('bg-pink-50');
  }

  dragLeave(event) {
    event.preventDefault();
    // Remove visual feedback
    event.currentTarget.classList.remove('bg-pink-50');
  }

  removeAudition(event) {
    event.preventDefault();
    event.stopPropagation();

    if (!confirm('Are you sure you want to remove this person from this audition session?')) {
      return;
    }

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
    // Remove visual feedback
    event.currentTarget.classList.remove('bg-pink-50');

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
    fetch("/manage/auditions/move_to_session", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name=csrf-token]').content
      },
      body: JSON.stringify({
        audition_id: auditionId,
        audition_session_id: newSessionId
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