# frozen_string_literal: true

# Where a production's casting stands, for the status line on its casting
# board and the "Cast and talent pool" card on its page (Tim, 2026-11-18:
# "Not set up", "Casting on" with counts, or "Off").
#
# Every count is of something that exists right now, so no line here can be
# only usually true:
#
#   roles     the production's own roles; in an act-based production, the
#             acts of its default lineup (intermissions and show roles
#             aren't acts)
#   pool      people in the talent pool it casts from, said only when it
#             casts from one (names typed in have no pool to count)
#   dates     the dates still to come that aren't canceled, and how many of
#             them have casting on
class CastingStatus
  attr_reader :production

  def initialize(production, pool_count: nil)
    @production = production
    @pool_count = pool_count
  end

  def state = production.casting_state

  def label
    { on: "Casting on", off: "Off", not_set_up: "Not set up" }.fetch(state)
  end

  # Tailwind classes for the label's badge.
  def badge
    { on: "bg-green-100 text-green-700", off: "bg-gray-100 text-gray-600", not_set_up: "bg-amber-100 text-amber-800" }.fetch(state)
  end

  def roles_count
    @roles_count ||= begin
      roles = production.roles.to_a
      production.act_based? ? roles.count { |role| !role.break? && !role.standing? } : roles.size
    end
  end

  def roles_words
    unit = production.act_based? ? "act" : "role"
    return production.act_based? ? "No lineup yet" : "No roles yet" if roles_count.zero?

    production.act_based? ? "#{roles_count} #{unit.pluralize(roles_count)} in the lineup" : "#{roles_count} #{unit.pluralize(roles_count)}"
  end

  def pool?
    production.casting_talent_pool?
  end

  def pool_count
    @pool_count ||= Person.joins(:talent_pool_memberships)
                          .where(talent_pool_memberships: { talent_pool_id: production.effective_talent_pool_ids })
                          .distinct.count
  end

  def pool_words
    return "People are added by name" unless pool?

    pool_count.zero? ? "Nobody in the talent pool yet" : "#{pool_count} in the talent pool"
  end

  # [dates with casting on, dates] among those still to come and not canceled.
  def upcoming
    @upcoming ||= begin
      scope = production.shows.where("date_and_time >= ?", Time.current).where(canceled: [ false, nil ])
      [ scope.where(casting_enabled: true).count, scope.count ]
    end
  end

  def dates_words
    on, total = upcoming
    return "No dates coming up" if total.zero?
    return "Casting is on for #{total == 1 ? 'the one date' : "all #{total} dates"} coming up" if on == total

    "Casting is on for #{on} of the #{total} dates coming up"
  end

  # The line after the label.
  def words
    case state
    when :on then [ roles_words, pool_words, dates_words ].join(" · ")
    when :off then "We don't cast people in #{production.name}."
    else "Casting isn't set up for #{production.name} yet."
    end
  end
end
