import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    setPrimaryHeadshot(event) {
        event.preventDefault()

        if (!confirm('Set this as your primary headshot?')) {
            return
        }

        const clickedItem = event.target.closest('.headshot-item')
        const headshotId = clickedItem.querySelector('input[name*="[id]"]')?.value

        if (!headshotId) {
            console.error('Could not find headshot ID')
            return
        }

        // Call the set_primary endpoint
        fetch(`/profile/headshots/${headshotId}/set_primary`, {
            method: 'PATCH',
            headers: {
                'Accept': 'text/vnd.turbo-stream.html',
                'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
            }
        })
            .then(response => response.text())
            .then(html => {
                Turbo.renderStreamMessage(html)
            })
            .catch(error => {
                console.error('Error setting primary:', error)
            })
    }

    addHeadshot(event) {
        const input = event.target
        const file = input.files[0]

        if (!file) return

        const container = document.getElementById('headshots-container')
        const template = document.getElementById('headshot-template')
        const newItem = template.content.cloneNode(true)

        // Generate unique ID for new record
        const timestamp = new Date().getTime()
        const inputs = newItem.querySelectorAll('input, select')
        inputs.forEach(input => {
            if (input.name) {
                input.name = input.name.replace('NEW_RECORD', timestamp)
            }
        })

        // Insert before the "Add" button (the border-dashed div itself)
        const addButton = container.querySelector('.border-dashed')
        if (addButton) {
            container.insertBefore(newItem, addButton)
        } else {
            container.appendChild(newItem)
        }

        // Get reference to the newly inserted item (now in the DOM)
        const insertedItem = addButton ? addButton.previousElementSibling : container.lastElementChild

        // Show preview
        const reader = new FileReader()
        reader.onload = (e) => {
            const preview = insertedItem.querySelector('img')
            if (preview) {
                preview.src = e.target.result
            }
        }
        reader.readAsDataURL(file)

        // Build FormData manually to include the file
        const form = document.getElementById('headshots-form')
        if (!form) {
            console.error('Could not find headshots-form')
            return
        }

        const formData = new FormData(form)

        // Add the file to the FormData with the correct name
        formData.append(`person[profile_headshots_attributes][${timestamp}][image]`, file)

        // Submit using fetch instead of form.requestSubmit()
        fetch(form.action, {
            method: form.method,
            body: formData,
            headers: {
                'Accept': 'text/vnd.turbo-stream.html',
                'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
            }
        })
            .then(response => response.text())
            .then(html => {
                // Let Turbo handle the response
                Turbo.renderStreamMessage(html)
            })
            .catch(error => {
                console.error('Error submitting form:', error)
            })

        // Clear the original input so the same file can be selected again
        input.value = ''
    }

    removeHeadshot(event) {
        event.preventDefault()

        if (!confirm('Remove this headshot?')) {
            return
        }

        const item = event.target.closest('.headshot-item')
        const destroyField = item.querySelector('.destroy-field')
        const idField = item.querySelector('input[name*="[id]"]')

        // If the headshot has an ID, it exists in the database - mark for destruction
        // If no ID, it's a new upload - remove from DOM completely
        if (idField && idField.value) {
            destroyField.value = '1'
            item.style.display = 'none'

            // Submit the form to persist the removal
            const form = document.getElementById('headshots-form')
            if (form) {
                form.requestSubmit()
            }
        } else {
            // New upload, just remove it
            item.remove()
        }
    }

    addResume(event) {
        const input = event.target
        const file = input.files[0]

        if (!file) return

        // The file will be handled by the form submission
        // Just update the UI to show the selected file
        const container = event.target.closest('.p-6')
        const existingPreview = container.querySelector('.w-48')

        if (existingPreview) {
            // Update existing preview
            const reader = new FileReader()
            reader.onload = (e) => {
                if (file.type === 'application/pdf') {
                    // Show PDF icon for PDFs
                    existingPreview.innerHTML = `
            <div class="w-full h-full flex flex-col items-center justify-center p-4">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-12 h-12 text-red-500 mb-2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
              </svg>
              <p class="text-xs text-center font-medium text-gray-700">${file.name}</p>
            </div>
          `
                } else {
                    // Show image preview
                    existingPreview.innerHTML = `<img src="${e.target.result}" class="w-full h-full object-cover transition-opacity group-hover:opacity-75">`
                }
            }
            reader.readAsDataURL(file)
        }
    }
}
