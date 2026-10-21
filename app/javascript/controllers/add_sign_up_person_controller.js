import { Controller } from "@hotwired/stimulus"

// Adding someone to a sign-up slot or its queue. The shared People Picker
// (shared/_people_picker, id "sign-up-picker") finds them; this registers
// the pick where the opener said: a slot, or the queue.
export default class extends Controller {
    static values = {
        registerUrl: String,
        registerQueueUrl: String,
        pickerId: { type: String, default: "sign-up-picker" }
    }

    // A slot's Add button.
    open(event) {
        event.preventDefault()
        event.stopPropagation()
        const slotId = event.currentTarget.dataset.slotId
        const slotName = event.currentTarget.dataset.slotName || `Slot ${slotId}`
        this.openPicker(`Add to ${slotName}`, { slot_id: slotId })
    }

    // The queue's Add button.
    openQueue(event) {
        event.preventDefault()
        event.stopPropagation()
        this.openPicker("Add to Queue", { instance_id: event.currentTarget.dataset.instanceId, queue: true })
    }

    openPicker(title, context) {
        window.dispatchEvent(new CustomEvent("people-picker:open", { detail: { id: this.pickerIdValue, title, context } }))
    }

    // people-picker:pick from the sheet.
    async picked(event) {
        const pick = event.detail
        if (pick.picker !== this.pickerIdValue || pick.type !== "Person") return
        const body = new FormData()
        body.append("person_id", pick.id)
        let url
        if (pick.context.queue) {
            if (!pick.context.instance_id) return
            body.append("instance_id", pick.context.instance_id)
            url = this.registerQueueUrlValue
        } else {
            if (!pick.context.slot_id) return
            body.append("slot_id", pick.context.slot_id)
            url = this.registerUrlValue
        }
        try {
            const response = await fetch(url, {
                method: "POST",
                headers: {
                    "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
                    Accept: "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"
                },
                body
            })
            if (!response.ok) throw new Error(`Registration failed: ${response.status}`)
            window.location.reload()
        } catch (error) {
            console.error(error)
            alert("Failed to add person. Please try again.")
        }
    }
}
