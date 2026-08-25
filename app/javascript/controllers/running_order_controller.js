import { Controller } from "@hotwired/stimulus"

// Editing an act-based show's running order straight on the casting board:
// drag acts (and intermissions) to reorder, add acts inline, remove them.
// Lives on the same element as drop-role so it survives the wholesale
// #show-roles swaps and can reuse drop-role's response-application helpers.
export default class extends Controller {
    static targets = [
        "list",
        "addActModal", "addActNameInput",
        "addActInShowSection", "addActInShowList",
        "addActDefaultSection", "addActDefaultList",
        "addActFrequentSection", "addActFrequentList",
        "addShowRoleModal", "addShowRoleNameInput", "addShowRoleQuantityInput",
        "editActModal", "editActTitle", "editActNameInput", "editActQuantityField", "editActQuantityInput",
        "removeActModal", "removeActTitle", "removeActBody", "removeActConfirm",
        "resetModal", "resetNewLineup",
        "resetMigratedSection", "resetMigratedList", "resetWipedSection", "resetWipedList"
    ]
    static values = { reorderUrl: String, actsUrl: String, optionsUrl: String, resetPreviewUrl: String, resetUrl: String }

    connect() {
        this.draggedElement = null
        this.dropIndicator = null
        this.pendingRemove = null
    }

    // The sibling drop-role controller owns the board-refresh helpers.
    get dropRole() {
        return this.application.getControllerForElementAndIdentifier(this.element, "drop-role")
    }

    items() {
        return this.hasListTarget ? [...this.listTarget.querySelectorAll("[data-running-order-item]")] : []
    }

    // ---- Drag to reorder ----

    startDrag(event) {
        this.draggedElement = event.target.closest("[data-running-order-item]")
        event.dataTransfer.effectAllowed = "move"
        event.dataTransfer.setData("text/plain", "running-order")
        this.draggedElement.classList.add("opacity-50")
    }

    endDrag() {
        if (!this.draggedElement) return
        this.draggedElement.classList.remove("opacity-50")
        this.draggedElement = null
        this.removeDropIndicator()
        this.saveOrder()
    }

    dragOver(event) {
        // People being dragged onto slots also cross this container — only
        // act drags started by this controller are ours to handle.
        if (!this.draggedElement) return
        event.preventDefault()
        event.dataTransfer.dropEffect = "move"

        const afterElement = this.getDragAfterElement(event.clientY)
        if (afterElement == null) {
            const last = this.items().filter(i => i !== this.draggedElement).pop()
            if (last) this.showDropIndicator(last, false)
            this.listTarget.appendChild(this.draggedElement)
        } else {
            this.showDropIndicator(afterElement, true)
            this.listTarget.insertBefore(this.draggedElement, afterElement)
        }
    }

    drop(event) {
        if (!this.draggedElement) return
        event.preventDefault()
        event.stopPropagation()
        this.removeDropIndicator()
    }

    getDragAfterElement(y) {
        return this.items().filter(item => item !== this.draggedElement).reduce((closest, child) => {
            const box = child.getBoundingClientRect()
            const offset = y - box.top - box.height / 2
            if (offset < 0 && offset > closest.offset) {
                return { offset: offset, element: child }
            }
            return closest
        }, { offset: Number.NEGATIVE_INFINITY }).element
    }

    // Touch support, mirroring role_order_controller
    touchStart(event) {
        this.draggedElement = event.target.closest("[data-running-order-item]")
        this.draggedElement.classList.add("opacity-50")
    }

    touchMove(event) {
        if (!this.draggedElement) return
        event.preventDefault()
        const y = event.touches[0].clientY
        const afterElement = this.getDragAfterElement(y)
        if (afterElement == null) {
            this.listTarget.appendChild(this.draggedElement)
        } else {
            this.listTarget.insertBefore(this.draggedElement, afterElement)
        }
    }

    touchEnd() {
        this.endDrag()
    }

    saveOrder() {
        const roleIds = this.items().map(item => item.dataset.runningOrderRoleId)
        this.post(this.reorderUrlValue, { role_ids: roleIds })
    }

    showDropIndicator(target, insertBefore) {
        this.removeDropIndicator()
        const indicator = document.createElement("div")
        indicator.className = "drop-indicator"
        indicator.style.cssText = "height: 3px; background-color: #ec4899; margin: -1.5px 0; border-radius: 2px; pointer-events: none;"
        target.parentNode.insertBefore(indicator, insertBefore ? target : target.nextSibling)
        this.dropIndicator = indicator
    }

    removeDropIndicator() {
        if (this.dropIndicator) {
            this.dropIndicator.remove()
            this.dropIndicator = null
        }
    }

    // ---- Add act ----

    openAddActModal() {
        if (!this.hasAddActModalTarget) return
        this.addActModalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")
        if (this.hasAddActNameInputTarget) {
            this.addActNameInputTarget.value = ""
            this.addActNameInputTarget.focus()
        }
        this.loadActOptions()
    }

    closeAddActModal() {
        if (this.hasAddActModalTarget) {
            this.addActModalTarget.classList.add("hidden")
        }
        document.body.classList.remove("overflow-hidden")
    }

    loadActOptions() {
        fetch(this.optionsUrlValue, { headers: { "Accept": "application/json" } })
            .then(r => r.json())
            .then(data => {
                this.fillOptionList(this.addActInShowSectionTarget, this.addActInShowListTarget, data.in_show || [], true)
                this.fillOptionList(this.addActDefaultSectionTarget, this.addActDefaultListTarget, data.from_default || [], false)
                this.fillFrequentList(data.frequent || [])
            })
            .catch(error => console.error("Failed to load act options:", error))
    }

    fillOptionList(section, list, options, showPerformers) {
        list.innerHTML = ""
        section.classList.toggle("hidden", options.length === 0)
        options.forEach(option => {
            const button = document.createElement("button")
            button.type = "button"
            button.className = "w-full flex items-center gap-2 p-2 border border-gray-200 rounded-lg text-left text-sm hover:border-pink-400 hover:bg-pink-50 transition-all cursor-pointer"
            button.addEventListener("click", () => this.addFromPicker(option.id))

            if (showPerformers && option.act_number) {
                const badge = document.createElement("span")
                badge.className = "flex-shrink-0 w-6 h-6 rounded-md bg-pink-100 text-pink-700 text-xs font-bold flex items-center justify-center"
                badge.textContent = option.act_number
                button.appendChild(badge)
            }

            const name = document.createElement("span")
            name.className = "font-medium text-gray-900"
            name.textContent = option.name
            button.appendChild(name)

            if (showPerformers && option.performers && option.performers.length) {
                const performers = document.createElement("span")
                performers.className = "text-xs text-gray-500 truncate"
                performers.textContent = option.performers.join(", ")
                button.appendChild(performers)
            }

            list.appendChild(button)
        })
    }

    // Act names this production keeps reusing — chips that add one by name.
    fillFrequentList(options) {
        if (!this.hasAddActFrequentSectionTarget || !this.hasAddActFrequentListTarget) return
        this.addActFrequentListTarget.innerHTML = ""
        this.addActFrequentSectionTarget.classList.toggle("hidden", options.length === 0)
        options.forEach(option => {
            const button = document.createElement("button")
            button.type = "button"
            button.className = "inline-flex items-center gap-1 px-2.5 py-1 border border-gray-200 rounded-full text-sm text-gray-700 hover:border-pink-400 hover:bg-pink-50 transition-all cursor-pointer"
            button.addEventListener("click", () => {
                this.closeAddActModal()
                this.post(this.actsUrlValue, { kind: "act", name: option.name })
            })

            const name = document.createElement("span")
            name.className = "font-medium"
            name.textContent = option.name
            button.appendChild(name)

            if (option.count && option.count > 1) {
                const count = document.createElement("span")
                count.className = "text-xs text-gray-400"
                count.textContent = `×${option.count}`
                button.appendChild(count)
            }

            this.addActFrequentListTarget.appendChild(button)
        })
    }

    addFromPicker(sourceRoleId) {
        this.closeAddActModal()
        this.post(this.actsUrlValue, { kind: "act", source_role_id: sourceRoleId })
    }

    addFreeText(event) {
        event.preventDefault()
        const name = this.hasAddActNameInputTarget ? this.addActNameInputTarget.value.trim() : ""
        if (!name) {
            this.addActNameInputTarget?.focus()
            return
        }
        this.closeAddActModal()
        this.post(this.actsUrlValue, { kind: "act", name: name })
    }

    addIntermission() {
        this.post(this.actsUrlValue, { kind: "break" })
    }

    // ---- Add show role ----

    openAddShowRoleModal() {
        if (!this.hasAddShowRoleModalTarget) return
        this.addShowRoleModalTarget.classList.remove("hidden")
        document.body.classList.add("overflow-hidden")
        if (this.hasAddShowRoleNameInputTarget) {
            this.addShowRoleNameInputTarget.value = ""
            this.addShowRoleNameInputTarget.focus()
        }
        if (this.hasAddShowRoleQuantityInputTarget) {
            this.addShowRoleQuantityInputTarget.value = "1"
        }
    }

    closeAddShowRoleModal() {
        if (this.hasAddShowRoleModalTarget) {
            this.addShowRoleModalTarget.classList.add("hidden")
        }
        document.body.classList.remove("overflow-hidden")
    }

    addShowRole(event) {
        event.preventDefault()
        const name = this.hasAddShowRoleNameInputTarget ? this.addShowRoleNameInputTarget.value.trim() : ""
        if (!name) {
            this.addShowRoleNameInputTarget?.focus()
            return
        }
        const quantity = this.hasAddShowRoleQuantityInputTarget ? parseInt(this.addShowRoleQuantityInputTarget.value, 10) || 1 : 1
        this.closeAddShowRoleModal()
        this.post(this.actsUrlValue, { kind: "show_role", name: name, quantity: quantity })
    }

    // ---- Edit (rename / resize) ----

    openEditModal(event) {
        const button = event.currentTarget
        this.pendingEdit = button.dataset.runningOrderRoleId
        const kind = button.dataset.runningOrderKind || "act"

        if (this.hasEditActTitleTarget) {
            const titles = { show_role: "Edit Show Role", intermission: "Rename Intermission", act: "Edit Act" }
            this.editActTitleTarget.textContent = titles[kind] || titles.act
        }
        if (this.hasEditActNameInputTarget) {
            this.editActNameInputTarget.value = button.dataset.runningOrderRoleName || ""
        }
        if (this.hasEditActQuantityFieldTarget) {
            this.editActQuantityFieldTarget.classList.toggle("hidden", kind !== "show_role")
        }
        if (this.hasEditActQuantityInputTarget) {
            this.editActQuantityInputTarget.value = button.dataset.runningOrderRoleQuantity || "1"
        }
        if (this.hasEditActModalTarget) {
            this.editActModalTarget.classList.remove("hidden")
            document.body.classList.add("overflow-hidden")
            this.editActNameInputTarget?.focus()
        }
    }

    closeEditModal() {
        this.pendingEdit = null
        if (this.hasEditActModalTarget) {
            this.editActModalTarget.classList.add("hidden")
        }
        document.body.classList.remove("overflow-hidden")
    }

    saveEdit(event) {
        event.preventDefault()
        const roleId = this.pendingEdit
        if (!roleId) return
        const name = this.hasEditActNameInputTarget ? this.editActNameInputTarget.value.trim() : ""
        if (!name) {
            this.editActNameInputTarget?.focus()
            return
        }
        const body = { name: name }
        if (this.hasEditActQuantityFieldTarget && !this.editActQuantityFieldTarget.classList.contains("hidden")) {
            body.quantity = parseInt(this.editActQuantityInputTarget.value, 10) || 1
        }
        this.closeEditModal()

        fetch(`${this.actsUrlValue}/${roleId}`, { method: "PATCH", headers: this.headers(), body: JSON.stringify(body) })
            .then(r => r.json())
            .then(data => this.handleResponse(data))
            .catch(error => {
                console.error("Failed to update:", error)
                alert("Failed to save. Please try again.")
            })
    }

    // ---- Reset to default lineup ----

    openResetModal() {
        if (!this.hasResetModalTarget) return
        fetch(this.resetPreviewUrlValue, { headers: { "Accept": "application/json" } })
            .then(r => r.json())
            .then(data => {
                this.fillResetPreview(data)
                this.resetModalTarget.classList.remove("hidden")
                document.body.classList.add("overflow-hidden")
            })
            .catch(error => {
                console.error("Failed to load reset preview:", error)
                alert("Failed to load the reset preview. Please try again.")
            })
    }

    fillResetPreview(data) {
        if (this.hasResetNewLineupTarget) {
            this.resetNewLineupTarget.innerHTML = ""
            ;(data.new_lineup || []).forEach(entry => {
                const li = document.createElement("li")
                if (entry.kind === "intermission") {
                    li.className = "text-gray-400"
                    li.textContent = `— ${entry.name} —`
                } else if (entry.kind === "show_role") {
                    li.textContent = `${entry.name} (show role)`
                } else {
                    li.textContent = `${entry.number}. ${entry.name}`
                }
                this.resetNewLineupTarget.appendChild(li)
            })
        }

        const fill = (section, list, entries, render) => {
            if (!section || !list) return
            list.innerHTML = ""
            section.classList.toggle("hidden", entries.length === 0)
            entries.forEach(entry => {
                const li = document.createElement("li")
                li.textContent = render(entry)
                list.appendChild(li)
            })
        }

        fill(this.hasResetMigratedSectionTarget && this.resetMigratedSectionTarget,
             this.hasResetMigratedListTarget && this.resetMigratedListTarget,
             data.migrated || [],
             entry => `${entry.name} stays in ${entry.to}`)
        fill(this.hasResetWipedSectionTarget && this.resetWipedSectionTarget,
             this.hasResetWipedListTarget && this.resetWipedListTarget,
             data.wiped || [],
             entry => `${entry.name} — cast in ${entry.from}, which goes away`)
    }

    closeResetModal() {
        if (this.hasResetModalTarget) {
            this.resetModalTarget.classList.add("hidden")
        }
        document.body.classList.remove("overflow-hidden")
    }

    resetConfirmed() {
        this.closeResetModal()
        this.post(this.resetUrlValue, {})
    }

    // ---- Remove act ----

    confirmRemove(event) {
        const button = event.currentTarget
        const roleId = button.dataset.runningOrderRoleId
        const label = button.dataset.runningOrderRoleLabel
        // "act", "intermission", or "show_role" — the modal names what it's removing
        const kind = button.dataset.runningOrderKind || "act"
        let names = []
        try { names = JSON.parse(button.dataset.runningOrderAssignmentNames || "[]") } catch { names = [] }

        this.pendingRemove = roleId
        const titles = { intermission: "Remove This Intermission?", show_role: "Remove This Show Role?", act: "Remove This Act?" }
        const confirms = { intermission: "Remove intermission", show_role: "Remove show role", act: "Remove act" }
        if (this.hasRemoveActTitleTarget) {
            this.removeActTitleTarget.textContent = titles[kind] || titles.act
        }
        if (this.hasRemoveActConfirmTarget) {
            const span = this.removeActConfirmTarget.querySelector("span")
            if (span) span.textContent = confirms[kind] || confirms.act
        }
        if (this.hasRemoveActBodyTarget) {
            let body
            if (kind === "intermission") {
                body = `Remove the ${label.toLowerCase()} from this show's running order?`
            } else if (kind === "show_role") {
                body = `Remove ${label} from this show?`
            } else {
                body = `Remove ${label} from this show's running order?`
            }
            if (names.length) {
                body += ` ${names.join(", ")} will be removed from this show with it.`
            }
            this.removeActBodyTarget.textContent = body
        }
        if (this.hasRemoveActModalTarget) {
            this.removeActModalTarget.classList.remove("hidden")
            document.body.classList.add("overflow-hidden")
        }
    }

    closeRemoveActModal() {
        this.pendingRemove = null
        if (this.hasRemoveActModalTarget) {
            this.removeActModalTarget.classList.add("hidden")
        }
        document.body.classList.remove("overflow-hidden")
    }

    removeConfirmed() {
        const roleId = this.pendingRemove
        this.closeRemoveActModal()
        if (!roleId) return

        fetch(`${this.actsUrlValue}/${roleId}?confirm=true`, {
            method: "DELETE",
            headers: this.headers()
        })
            .then(r => r.json())
            .then(data => this.handleResponse(data))
            .catch(error => {
                console.error("Failed to remove act:", error)
                alert("Failed to remove the act. Please try again.")
            })
    }

    // ---- Shared plumbing ----

    stopPropagation(event) {
        event.stopPropagation()
    }

    headers() {
        return {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content
        }
    }

    post(url, body) {
        fetch(url, { method: "POST", headers: this.headers(), body: JSON.stringify(body) })
            .then(r => r.json())
            .then(data => this.handleResponse(data))
            .catch(error => {
                console.error("Running order update failed:", error)
                alert("Failed to update the running order. Please try again.")
            })
    }

    handleResponse(data) {
        if (!data) return
        if (data.error) {
            alert(data.error)
            return
        }

        if (data.roles_html) {
            document.getElementById("show-roles").outerHTML = data.roles_html
        }
        if (data.roles_config_html) {
            const bar = document.getElementById("roles-config-bar")
            if (bar) bar.innerHTML = data.roles_config_html
        }

        const dropRole = this.dropRole
        if (dropRole) {
            if (data.cast_members_html) dropRole.updateCastMembersList(data.cast_members_html)
            if (data.linkage_sync_html) dropRole.updateLinkageSyncSection(data.linkage_sync_html)
            dropRole.updateProgressBar(data.progress)
            dropRole.updateFinalizeSection(data.notify_modal_html)
        }
    }
}
