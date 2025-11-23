import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    setPrimaryHeadshot(event) {
        event.preventDefault()

        if (!confirm('Set this as your primary headshot?')) {
            return
        }

        const container = document.getElementById('headshots-container')

        // Remove all primary badges and set all is_primary fields to false
        container.querySelectorAll('.headshot-item').forEach(item => {
            const badge = item.querySelector('.primary-badge')
            if (badge) badge.remove()

            const primaryField = item.querySelector('.is-primary-field')
            if (primaryField) primaryField.value = '0'

            // Show the "Set as Primary" button for all headshots
            const primaryBtn = item.querySelector('.set-primary-btn')
            if (primaryBtn) {
                primaryBtn.classList.remove('hidden')
                primaryBtn.replaceWith(primaryBtn.cloneNode(true))
            } else {
                // If button doesn't exist (was primary), recreate it
                const btnContainer = item.querySelector('.mt-2')
                if (btnContainer) {
                    const existingText = btnContainer.querySelector('.text-gray-500')
                    if (existingText) {
                        const newBtn = document.createElement('button')
                        newBtn.type = 'button'
                        newBtn.className = 'text-xs text-pink-500 hover:text-pink-600 underline cursor-pointer set-primary-btn'
                        newBtn.setAttribute('data-action', 'click->profile-files#setPrimaryHeadshot')
                        newBtn.textContent = 'Set as Primary'
                        existingText.replaceWith(newBtn)
                    }
                }
            }
        })

        // Set this headshot as primary
        const clickedItem = event.target.closest('.headshot-item')
        if (clickedItem) {
            const primaryField = clickedItem.querySelector('.is-primary-field')
            if (primaryField) primaryField.value = '1'

            // Add primary badge
            const imageContainer = clickedItem.querySelector('.aspect-\\[3\\/4\\]')
            if (imageContainer && !imageContainer.querySelector('.primary-badge')) {
                const badge = document.createElement('span')
                badge.className = 'primary-badge absolute top-2 right-2 bg-pink-500 text-white text-xs font-medium px-2 py-1 rounded'
                badge.textContent = 'Primary'
                imageContainer.appendChild(badge)
            }

            // Replace button with text
            event.target.replaceWith(
                Object.assign(document.createElement('span'), {
                    className: 'text-xs text-gray-500 italic',
                    textContent: 'Primary'
                })
            )
        }
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

        // Set up file input for the new item
        const fileInput = document.createElement('input')
        fileInput.type = 'file'
        fileInput.name = `person[profile_headshots_attributes][${timestamp}][image]`
        fileInput.style.display = 'none'
        const dataTransfer = new DataTransfer()
        dataTransfer.items.add(file)
        fileInput.files = dataTransfer.files
        newItem.querySelector('.headshot-item').appendChild(fileInput)

        // Show preview
        const reader = new FileReader()
        reader.onload = (e) => {
            newItem.querySelector('.new-headshot-preview').src = e.target.result
            // Show the preview div once image is loaded
            const previewDiv = newItem.querySelector('.aspect-\\[3\\/4\\]')
            if (previewDiv) {
                previewDiv.classList.remove('bg-gray-50')
            }
        }
        reader.readAsDataURL(file)

        // Insert before the "Add" button
        const addButton = container.querySelector('.border-dashed')?.parentElement
        if (addButton) {
            container.insertBefore(newItem, addButton)
        } else {
            container.appendChild(newItem)
        }

        // Clear the input so the same file can be selected again
        input.value = ''

        // Submit the form immediately
        const form = input.closest('form')
        if (form) {
            form.requestSubmit()
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
