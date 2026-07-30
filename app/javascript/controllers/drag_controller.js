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

            // Get the filter from the URL parameters
            const urlParams = new URLSearchParams(window.location.search);
            const filter = urlParams.get('filter') || 'to_be_scheduled';

            // Send AJAX request to create audition and add to session
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
                .then(response => response.json())
                .then(data => {
                    // Update the right list (sign-ups)
                    const rightList = document.querySelector("#right_list");
                    if (rightList && data.right_list_html) {
                        rightList.outerHTML = data.right_list_html;
                    }
                    // Update the entire sessions list
                    const sessionsList = document.querySelector("#audition_sessions_list");
                    if (sessionsList && data.sessions_list_html) {
                        sessionsList.outerHTML = data.sessions_list_html;
                    }
                })
                .catch(error => console.error('Error:', error));
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
            .then(response => response.json())
            .then(data => {
                // Update the right list (sign-ups) - just update innerHTML, not the container
                if (data.right_list_html) {
                    const rightList = document.querySelector("#right_list");
                    if (rightList) {
                        // Parse the returned HTML which includes <div id="right_list">...</div>
                        const parser = new DOMParser();
                        const doc = parser.parseFromString(data.right_list_html, 'text/html');
                        const newContent = doc.querySelector('#right_list');
                        if (newContent) {
                            rightList.innerHTML = newContent.innerHTML;
                        }
                    }
                }
                // Update the entire sessions list - just update innerHTML, not the container
                if (data.sessions_list_html) {
                    const sessionsList = document.querySelector("#audition_sessions_list");
                    if (sessionsList) {
                        // Parse the returned HTML which includes <div id="audition_sessions_list">...</div>
                        const parser = new DOMParser();
                        const doc = parser.parseFromString(data.sessions_list_html, 'text/html');
                        const newContent = doc.querySelector('#audition_sessions_list');
                        if (newContent) {
                            sessionsList.innerHTML = newContent.innerHTML;
                        }
                    }
                }
            })
            .catch(error => console.error('Error:', error));
    }
}
