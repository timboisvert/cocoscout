# frozen_string_literal: true

# How a person's assignments read when they're listed together.
#
# In an act-based show one performer may hold the same-named act more than
# once ("Magic" in each half). Listing "Magic, Magic" (or "Act 1 · Magic,
# Act 3 · Magic") says less than grouping does, so same-named acts collapse:
#
#   one act  -> "Magic (Act 3)"
#   several  -> "2 acts as Magic (Acts 1 and 3)"
#
# A show role (MC, Stage Kitten — a standing role alongside the lineup) has
# no act number and reads by name, listed first: "MC, Magic (Act 3)".
#
# In a role-based show the labels are just the distinct role names, so a
# caller can use this everywhere a person's assignments are listed and only
# act-based shows read differently. Breaks (intermissions) are never listed.
#
# Pass `numbers:` (see CastingHelper#lineup_numbers) when labelling many
# people on one show, so the lineup isn't re-read per person.
class ActAssignmentLabeler
  # A label that leads with a count ("2 acts as Magic …") already carries its
  # own "as"; a sentence putting a name in front of it reads "Tim in …".
  COUNTED_LABEL = /\A\d+ acts as /

  def self.labels(assignments, show:, numbers: nil)
    new(assignments, show: show, numbers: numbers).labels
  end

  # "as" before "Magic (Act 3)" or a plain role name; "in" before
  # "2 acts as Magic (Acts 1 and 3)".
  def self.connector(label)
    label.to_s.match?(COUNTED_LABEL) ? "in" : "as"
  end

  def initialize(assignments, show:, numbers: nil)
    @roles = Array(assignments).map { |a| a.respond_to?(:role) ? a.role : a }.compact.reject(&:break?).uniq
    @show = show
    @numbers = numbers
  end

  def labels
    return [] if @roles.empty?
    return @roles.map(&:name).uniq unless @show&.act_based?

    numbers = @numbers || Role.lineup_numbers_for(@show.available_roles.to_a)
    numbered = @roles.map { |role| [ role, numbers[role.id] || role.lineup_number(show: @show) ] }
    # Show roles (no number) lead; acts follow in running order.
    numbered.sort_by! { |_, n| n || -1 }
    numbered.group_by { |role, _| role.name.to_s.downcase.strip }.values.map { |group| label_for(group) }
  end

  private

  def label_for(group)
    name = group.first.first.name
    nums = group.filter_map(&:last)
    return name if nums.empty?
    return "#{name} (Act #{nums.first})" if group.size == 1

    "#{group.size} acts as #{name} (Acts #{nums.to_sentence})"
  end
end
