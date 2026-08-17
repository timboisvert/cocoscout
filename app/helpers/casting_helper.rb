module CastingHelper
  # ---- Casting mode vocabulary --------------------------------------------
  #
  # A role-based production fills "roles"; an act-based one casts "acts" in a
  # "lineup". Every view that names the unit goes through these so the words
  # follow the casting mode. Pass the Show when rendering one event (a show
  # may override its production's mode) and the Production for
  # production-wide pages.

  # "role" / "roles" / "Role" / "Roles" — or "act" / "acts" / "Act" / "Acts".
  def casting_unit(context, plural: false, capitalize: false)
    word = context&.act_based? ? "act" : "role"
    word = word.pluralize if plural
    capitalize ? word.capitalize : word
  end

  # The name of the structure being edited: "Roles" or "Lineup".
  def casting_structure_label(context)
    context&.act_based? ? "Lineup" : "Roles"
  end

  # Running-order numbers for a lineup, { role_id => n }, breaks omitted.
  # Compute once per page and pass into Role#display_name(number:). With
  # show:, the numbers are for that show — empty when it isn't cast by acts.
  def lineup_numbers(roles, show: nil)
    return {} if show && !show.act_based?

    Role.lineup_numbers_for(roles)
  end

  # "Act 3 · Magic" in an act-based lineup, the plain name otherwise.
  # Accepts the precomputed lineup_numbers hash to avoid a query per role,
  # and show: so a production role read inside an overridden show follows
  # that show's mode.
  def role_display_name(role, numbers = nil, show: nil)
    return "" unless role

    role.display_name(number: numbers && numbers[role.id], show: show)
  end

  # Maps a role's assignments onto its display slots (1..quantity).
  #
  # Exact in-range positions claim their slot first; everything else
  # (nil/0 position, duplicate position, out-of-range position) fills the
  # remaining slots in order. Overfull roles extend past quantity rather
  # than hiding anyone, so a cast assignment is never dropped from display
  # because of bad position data.
  #
  # Returns a hash of slot_position => assignment. Render with:
  #   slots = cast_assignments_by_slot(role, assignments)
  #   total = cast_total_slots(role, slots)
  #   (1..total).each { |i| slots[i] ... }
  def cast_assignments_by_slot(role, assignments)
    quantity = role.quantity || 1
    slots = {}
    unplaced = []

    Array(assignments).sort_by { |a| a.position || 0 }.each do |a|
      pos = a.position
      if pos.present? && pos >= 1 && pos <= quantity && slots[pos].nil?
        slots[pos] = a
      else
        unplaced << a
      end
    end

    next_slot = 1
    unplaced.each do |a|
      next_slot += 1 while slots[next_slot]
      slots[next_slot] = a
      next_slot += 1
    end

    slots
  end

  # Number of slots to render for a role: its quantity, extended if
  # overfull position data pushed assignments past the last slot.
  def cast_total_slots(role, slots)
    [ role.quantity || 1, slots.keys.max || 0 ].max
  end
end
