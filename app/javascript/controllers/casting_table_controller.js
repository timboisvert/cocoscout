import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cell", "roleSelector", "roleOptions", "showCount", "memberCount", "totalCount", "draftAssignmentCount"]
  static values = { tableId: Number }

  connect() {
    this.rolesData = JSON.parse(document.getElementById('roles-data').textContent)
    this.roleCountsData = JSON.parse(document.getElementById('role-counts-data').textContent)
    this.currentCell = null
    
    // Close popup when clicking outside
    document.addEventListener('click', this.handleOutsideClick.bind(this))
    // Close popup on escape key
    document.addEventListener('keydown', this.handleKeydown.bind(this))
  }

  disconnect() {
    document.removeEventListener('click', this.handleOutsideClick.bind(this))
    document.removeEventListener('keydown', this.handleKeydown.bind(this))
  }

  handleKeydown(event) {
    if (event.key === 'Escape') {
      this.closeRoleSelector()
    }
  }

  handleOutsideClick(event) {
    if (this.roleSelectorTarget.classList.contains('hidden')) return
    
    if (!this.roleSelectorTarget.contains(event.target) && 
        !event.target.closest('[data-action*="openRoleSelector"]')) {
      this.closeRoleSelector()
    }
  }

  openRoleSelector(event) {
    event.stopPropagation()
    
    const cell = event.target.closest('[data-casting-table-target="cell"]')
    if (!cell) return

    this.currentCell = cell
    const showId = cell.dataset.showId
    const memberType = cell.dataset.memberType
    const memberId = cell.dataset.memberId

    // Get roles for this show (now keyed by showId instead of productionId)
    const roles = this.rolesData[showId] || []
    
    // Check if this cell has a draft assignment (pink background)
    const hasDraftAssignment = cell.querySelector('.bg-pink-500') !== null
    
    // Calculate total assignments vs total slots for this show
    let totalAssigned = 0
    let totalSlots = 0
    roles.forEach(role => {
      const countKey = `${showId}_${role.id}`
      totalAssigned += this.roleCountsData[countKey] || 0
      totalSlots += role.quantity
    })
    const isShowFullyCast = totalSlots > 0 && totalAssigned >= totalSlots
    
    // Build role options
    this.roleOptionsTarget.innerHTML = ''
    
    // If show is fully cast and this cell doesn't have a draft assignment, show message only
    if (isShowFullyCast && !hasDraftAssignment) {
      this.roleOptionsTarget.innerHTML = '<div class="text-xs text-gray-500 py-2">Show is fully cast</div>'
    } else if (roles.length === 0) {
      this.roleOptionsTarget.innerHTML = '<div class="text-xs text-gray-500 py-2">No roles defined</div>'
    } else {
      // Get the member name for this cell by finding the corresponding header
      const cellIndex = Array.from(cell.parentElement.children).indexOf(cell)
      const headerRow = cell.closest('table').querySelector('thead tr')
      const headerCell = headerRow?.children[cellIndex]
      const memberName = headerCell?.querySelector('span[title]')?.getAttribute('title') || 'this person'
      
      // Only show role options if show is not fully cast
      if (!isShowFullyCast) {
        roles.forEach(role => {
          // Check if role is at capacity for this show
          const countKey = `${showId}_${role.id}`
          const currentCount = this.roleCountsData[countKey] || 0
          const isRoleFullyCast = currentCount >= role.quantity
          const availableSlots = role.quantity - currentCount
          
          // For restricted roles, check if this member is eligible
          let isEligible = true
          if (role.restricted && role.eligible_members) {
            isEligible = role.eligible_members.some(m => m.type === memberType && m.id === parseInt(memberId))
          }
          
          const button = document.createElement('button')
          button.type = 'button'
          button.dataset.roleId = role.id
          button.dataset.roleName = role.name
          
          // Build label with slot info
          let label = role.name
          if (isRoleFullyCast) {
            label = `${role.name} (Fully cast)`
          } else if (role.quantity > 1) {
            label = `${role.name} (${currentCount} cast, ${availableSlots} available)`
          }
          
          if (isRoleFullyCast) {
            button.className = 'w-full text-left px-3 py-2 text-sm rounded text-gray-400 cursor-not-allowed'
            button.textContent = label
            button.disabled = true
          } else if (role.restricted && !isEligible) {
            // Show restricted role with warning
            button.className = 'w-full text-left px-3 py-2 text-sm rounded text-amber-600 hover:bg-amber-50 transition-colors cursor-pointer'
            button.innerHTML = `<span class="flex items-center gap-1"><svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/></svg>${label} (Not eligible)</span>`
            button.addEventListener('click', (e) => {
              e.stopPropagation()
              this.showRestrictedRoleConfirmation(role, showId, memberType, memberId, memberName)
            })
          } else {
            button.className = 'w-full text-left px-3 py-2 text-sm rounded hover:bg-pink-50 hover:text-pink-700 transition-colors cursor-pointer'
            button.textContent = label
            button.addEventListener('click', () => this.assignRole(role.id, showId, memberType, memberId))
          }
          
          this.roleOptionsTarget.appendChild(button)
        })
      }

      // Add "Remove Assignment" option if cell has a draft assignment
      if (hasDraftAssignment) {
        const divider = document.createElement('div')
        divider.className = 'border-t border-gray-200 my-1'
        this.roleOptionsTarget.appendChild(divider)

        const clearButton = document.createElement('button')
        clearButton.type = 'button'
        clearButton.className = 'w-full text-left px-3 py-2 text-sm rounded text-red-600 hover:bg-red-50 transition-colors cursor-pointer'
        clearButton.textContent = 'Remove Assignment'
        clearButton.addEventListener('click', () => this.unassignRole(showId, memberType, memberId))
        this.roleOptionsTarget.appendChild(clearButton)
      }
    }

    // Position the popup near the cell
    const rect = cell.getBoundingClientRect()
    const popup = this.roleSelectorTarget
    
    popup.classList.remove('hidden')
    
    // Position to the right of the cell if there's room, otherwise to the left
    const popupWidth = popup.offsetWidth
    const spaceOnRight = window.innerWidth - rect.right
    
    if (spaceOnRight >= popupWidth + 10) {
      popup.style.left = `${rect.right + 5}px`
    } else {
      popup.style.left = `${rect.left - popupWidth - 5}px`
    }
    
    popup.style.top = `${rect.top + window.scrollY}px`
  }

  closeRoleSelector() {
    this.roleSelectorTarget.classList.add('hidden')
    this.currentCell = null
  }

  async assignRole(roleId, showId, memberType, memberId) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]').content

    try {
      const response = await fetch(`/manage/casting/tables/${this.tableIdValue}/assign`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({
          show_id: showId,
          role_id: roleId,
          assignable_type: memberType,
          assignable_id: memberId
        })
      })

      const data = await response.json()

      if (response.ok) {
        // Update the cell to show the assignment
        this.updateCellWithAssignment(this.currentCell, data.role_name)
        this.closeRoleSelector()
        // Update the role counts data for future checks
        const countKey = `${showId}_${roleId}`
        this.roleCountsData[countKey] = (this.roleCountsData[countKey] || 0) + 1
        // Update tally displays
        this.updateTallyCounts(showId, memberType, memberId, 1)
        // Update draft assignment count in the floating bar
        this.updateDraftAssignmentCount(1)
      } else {
        alert(data.error || 'Error assigning role')
      }
    } catch (error) {
      console.error('Error:', error)
      alert('Error assigning role')
    }
  }

  async unassignRole(showId, memberType, memberId) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]').content

    try {
      const response = await fetch(`/manage/casting/tables/${this.tableIdValue}/unassign`, {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({
          show_id: showId,
          assignable_type: memberType,
          assignable_id: memberId
        })
      })

      const data = await response.json()

      if (response.ok) {
        this.updateCellWithUnassignment(this.currentCell)
        this.closeRoleSelector()
        // Update the role counts data - find the matching show role by name
        if (data.role_name) {
          const roles = this.rolesData[showId] || []
          const matchingRole = roles.find(r => r.name === data.role_name)
          if (matchingRole) {
            const countKey = `${showId}_${matchingRole.id}`
            this.roleCountsData[countKey] = Math.max(0, (this.roleCountsData[countKey] || 0) - 1)
          }
        }
        // Update tally displays (decrement)
        this.updateTallyCounts(showId, memberType, memberId, -1)
        // Update draft assignment count in the floating bar
        this.updateDraftAssignmentCount(-1)
      } else {
        alert(data.error || 'Error removing assignment')
      }
    } catch (error) {
      console.error('Error:', error)
      alert('Error removing assignment')
    }
  }

  updateCellWithAssignment(cell, roleName) {
    const inner = cell.querySelector('div')
    inner.className = 'w-full h-full min-h-[40px] bg-pink-500 text-white rounded flex items-center justify-center cursor-pointer text-xs font-medium px-1'
    inner.innerHTML = roleName.substring(0, 10)
    inner.title = roleName
  }

  updateCellWithUnassignment(cell) {
    const availability = cell.dataset.availability
    const inner = cell.querySelector('div')
    inner.className = 'w-full h-full min-h-[40px] rounded flex items-center justify-center cursor-pointer hover:bg-gray-100'
    inner.title = ''
    
    let display = '-'
    let colorClass = 'text-gray-300'
    
    if (availability === 'available') {
      display = 'A'
      colorClass = 'text-pink-500'
    } else if (availability === 'unavailable') {
      display = 'U'
      colorClass = 'text-gray-400'
    }
    
    inner.innerHTML = `<span class="text-sm font-medium ${colorClass}">${display}</span>`
  }

  updateTallyCounts(showId, memberType, memberId, delta) {
    // Update show count (right column)
    const showCountCell = this.showCountTargets.find(el => el.dataset.showId === showId.toString())
    if (showCountCell) {
      let currentCount = parseInt(showCountCell.dataset.currentCount) || 0
      const totalSlots = parseInt(showCountCell.dataset.totalSlots) || 0
      currentCount += delta
      showCountCell.dataset.currentCount = currentCount
      
      const textEl = showCountCell.querySelector('.show-count-text')
      if (textEl) {
        textEl.textContent = `${currentCount}/${totalSlots}`
      }
      
      // Update fully cast icon
      const existingIcon = showCountCell.querySelector('.fully-cast-icon')
      if (currentCount >= totalSlots && totalSlots > 0) {
        if (!existingIcon) {
          const iconHtml = `<svg class="w-3.5 h-3.5 text-pink-500 fully-cast-icon" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
          </svg>`
          textEl.insertAdjacentHTML('beforebegin', iconHtml)
        }
      } else if (existingIcon) {
        existingIcon.remove()
      }
    }

    // Update member count (bottom row)
    const memberCountCell = this.memberCountTargets.find(el => 
      el.dataset.memberType === memberType && el.dataset.memberId === memberId.toString()
    )
    if (memberCountCell) {
      let currentCount = parseInt(memberCountCell.dataset.currentCount) || 0
      currentCount += delta
      memberCountCell.dataset.currentCount = currentCount
      
      const badge = memberCountCell.querySelector('.member-count-text')
      if (badge) {
        badge.textContent = currentCount
        if (currentCount > 0) {
          badge.className = 'inline-flex items-center justify-center w-6 h-6 rounded-full bg-pink-100 text-pink-700 text-xs font-medium member-count-text'
        } else {
          badge.className = 'inline-flex items-center justify-center w-6 h-6 rounded-full bg-gray-100 text-gray-500 text-xs font-medium member-count-text'
        }
      }
    }

    // Update total count (bottom right corner)
    if (this.hasTotalCountTarget) {
      const totalCell = this.totalCountTarget
      let currentCount = parseInt(totalCell.dataset.currentCount) || 0
      const totalSlots = parseInt(totalCell.dataset.totalSlots) || 0
      currentCount += delta
      totalCell.dataset.currentCount = currentCount
      
      const textEl = totalCell.querySelector('.total-count-text')
      if (textEl) {
        textEl.textContent = `${currentCount}/${totalSlots}`
        if (currentCount >= totalSlots) {
          textEl.className = 'text-xs font-semibold text-pink-600 total-count-text'
        } else {
          textEl.className = 'text-xs font-semibold text-gray-700 total-count-text'
        }
      }
    }
  }

  updateDraftAssignmentCount(delta) {
    if (!this.hasDraftAssignmentCountTarget) return
    
    const countEl = this.draftAssignmentCountTarget
    let currentCount = parseInt(countEl.textContent) || 0
    currentCount += delta
    currentCount = Math.max(0, currentCount) // Don't go negative
    countEl.textContent = currentCount
  }

  showRestrictedRoleConfirmation(role, showId, memberType, memberId, memberName) {
    // Build the list of eligible members
    const eligibleNames = role.eligible_members?.map(m => m.name).join(', ') || 'No one'
    
    // Build confirmation content
    this.roleOptionsTarget.innerHTML = `
      <div class="space-y-3">
        <div class="text-sm">
          <div class="flex items-center gap-1 text-amber-600 font-medium mb-1">
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
            </svg>
            ${role.name} is restricted
          </div>
          <p class="text-gray-600 text-xs mb-2">
            <span class="font-medium">${memberName}</span> is not eligible for this role.
          </p>
          <p class="text-gray-500 text-xs">
            <span class="font-medium">Eligible:</span> ${eligibleNames}
          </p>
        </div>
        <div class="flex gap-2 pt-1">
          <button type="button" id="cancel-restricted-btn" class="flex-1 px-3 py-1.5 text-xs rounded border border-gray-300 text-gray-700 hover:bg-gray-50 transition-colors">
            Cancel
          </button>
          <button type="button" id="confirm-restricted-btn" class="flex-1 px-3 py-1.5 text-xs rounded bg-amber-500 text-white hover:bg-amber-600 transition-colors">
            Assign Anyway
          </button>
        </div>
      </div>
    `
    
    // Add event listeners
    document.getElementById('cancel-restricted-btn').addEventListener('click', () => {
      this.closeRoleSelector()
    })
    
    document.getElementById('confirm-restricted-btn').addEventListener('click', () => {
      this.assignRole(role.id, showId, memberType, memberId)
    })
  }
}
