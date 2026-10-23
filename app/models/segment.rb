# frozen_string_literal: true

# Followers picked by what they did (Mailing lists, V1.1): "Regulars",
# "Haven't been back", "Dan's crowd, not ours yet". A segment keeps itself
# current; nobody maintains it. Its rule:
#
#   { "match" => "all" | "any",
#     "conditions" => [
#       { "type" => "on_list", "list_id" => 3 },
#       { "type" => "bought", "target" => "production:12" | "list:3" | "type:in_house" | "type:third_party" | "any" },
#       { "type" => "never_bought", "target" => ... },
#       { "type" => "times_at_least", "count" => 3 },
#       { "type" => "last_bought", "when" => "before" | "after", "date" => "2026-07-01" },
#       { "type" => "joined_from", "kind" => "checkout" | "manual" | ... } ] }
class Segment < ApplicationRecord
  CONDITION_TYPES = %w[on_list bought never_bought times_at_least last_bought joined_from].freeze

  belongs_to :organization

  normalizes :name, with: ->(name) { name.to_s.squish }

  validates :name, presence: true
  validate :rule_shape

  def conditions
    Array(rule["conditions"]).select { |c| c.is_a?(Hash) && CONDITION_TYPES.include?(c["type"]) }
  end

  def match_any? = rule["match"] == "any"

  # The organization's followers this segment picks, subscribed or not; a
  # send narrows it to who can be emailed.
  def followers
    SegmentQuery.new(organization, rule).followers
  end

  # One line saying what it picks, for the list of segments.
  def summary
    words = conditions.map { |condition| SegmentQuery.describe(organization, condition) }.compact
    return "Everyone on your lists" if words.empty?

    words.join(match_any? ? ", or " : ", and ")
  end

  private

  def rule_shape
    errors.add(:rule, "needs at least one rule") if conditions.empty?
  end
end
