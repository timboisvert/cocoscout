import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["modal", "modalContent"]

    connect() {
        this.isDirty = false;
        window.addEventListener('beforeunload', this.handleBeforeUnload.bind(this));
    }

    disconnect() {
        window.removeEventListener('beforeunload', this.handleBeforeUnload.bind(this));
    }

    handleBeforeUnload(event) {
        if (this.isDirty) {
            event.preventDefault();
            event.returnValue = 'You have unsaved changes. Are you sure you want to leave?';
            return event.returnValue;
        }
    }

    markDirty() {
        this.isDirty = true;
    }

    markClean() {
        this.isDirty = false;
    }

    editHeaderText(event) {
        event.preventDefault();
        const instructionTextContent = document.querySelector('#header_text_display').innerHTML;
        const modalContent = `
            <div class="bg-white px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                <h3 class="text-lg font-medium leading-6 text-gray-900 mb-4">Edit Instruction Text</h3>
                <form id="header-text-form" data-action="submit->questionnaire-builder#saveHeaderText">
                    <trix-editor input="instruction_text_input" class="trix-content border border-gray-300 rounded-lg"></trix-editor>
                    <input id="instruction_text_input" type="hidden" name="instruction_text">
                    <div class="mt-5 sm:mt-6 sm:grid sm:grid-flow-row-dense sm:grid-cols-2 sm:gap-3">
                        <button type="submit" class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-pink-500 text-base font-medium text-white hover:bg-pink-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-pink-500 sm:col-start-2 sm:text-sm">
                            Save
                        </button>
                        <button type="button" data-action="click->questionnaire-builder#closeModal" class="mt-3 w-full inline-flex justify-center rounded-md border border-gray-300 shadow-sm px-4 py-2 bg-white text-base font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-pink-500 sm:mt-0 sm:col-start-1 sm:text-sm">
                            Cancel
                        </button>
                    </div>
                </form>
            </div>
        `;
        
        this.showModal(modalContent);
        
        // Set the initial content
        const editor = document.querySelector('trix-editor');
        if (editor) {
            // Extract text content from the display div
            const tempDiv = document.createElement('div');
            tempDiv.innerHTML = instructionTextContent;
            const textContent = tempDiv.textContent || tempDiv.innerText || '';
            
            // Only set if there's actual content (not the placeholder text)
            if (textContent.trim() && !textContent.includes('Click to add instruction text')) {
                editor.editor.loadHTML(instructionTextContent);
            }
        }
    }

    async saveHeaderText(event) {
        event.preventDefault();
        const form = event.target;
        const instructionText = form.querySelector('#instruction_text_input').value;
        const url = form.closest('[data-controller="questionnaire-builder"]').dataset.updateHeaderTextUrl || 
                    window.location.pathname.replace('/build', '/update_header_text');
        
        try {
            const response = await fetch(url, {
                method: 'PATCH',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
                    'Accept': 'text/vnd.turbo-stream.html'
                },
                body: JSON.stringify({ instruction_text: instructionText })
            });
            
            if (response.ok) {
                const turboStream = await response.text();
                Turbo.renderStreamMessage(turboStream);
                this.closeModal();
                this.markClean();
            }
        } catch (error) {
            console.error('Error saving header text:', error);
        }
    }

    showModal(content) {
        if (this.hasModalTarget && this.hasModalContentTarget) {
            this.modalContentTarget.innerHTML = content;
            this.modalTarget.classList.remove('hidden');
        }
    }

    closeModal() {
        if (this.hasModalTarget) {
            this.modalTarget.classList.add('hidden');
            this.modalContentTarget.innerHTML = '';
        }
    }
}
