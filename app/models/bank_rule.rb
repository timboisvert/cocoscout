# frozen_string_literal: true

# A rule for the bank page (Books V1.3, plan D3; Tim, 2026-11-02): when the
# bank's description contains a phrase (any of several, separated by
# commas), and the money goes the way the rule says, the line is recorded
# as a given category and payee, or ignored. Rules run over the lines
# waiting when one is made or applied, and over every statement brought
# in later while on_import is on (BankRules).
class BankRule < ApplicationRecord
  DIRECTIONS = %w[any in out].freeze
  ACTIONS = %w[record ignore].freeze

  belongs_to :organization
  belongs_to :production, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  validates :contains, presence: true
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :action, inclusion: { in: ACTIONS }
  validates :direction, inclusion: { in: %w[in out], message: "must be money in or money out to record it" }, if: :record?
  validates :category_key, presence: true, if: :record?
  validate :production_is_ours

  before_validation { self.contains = contains.to_s.split(",").map { |s| s.strip.squeeze(" ") }.compact_blank.join(", ") }

  scope :on_import, -> { where(on_import: true) }

  def record? = action == "record"
  def ignore? = action == "ignore"

  # The phrases, each one enough on its own.
  def phrases = contains.to_s.split(",").map(&:strip).compact_blank

  def matches?(line)
    return false if direction == "in" && !line.deposit?
    return false if direction == "out" && line.deposit?

    text = line.description.to_s.downcase
    phrases.any? { |p| text.include?(p.downcase) }
  end

  # The lines waiting that this rule fits.
  def waiting_lines
    organization.bank_statement_lines.to_deal_with.select { |line| matches?(line) }
  end

  def category_label
    return nil unless record?

    MoneyCategories.label_for(category_key, direction == "in" ? :income : :spending, organization: organization)
  end

  # What it does, in words: "Record as Bar purchases, Restaurant Depot" or "Ignore".
  def does
    return "Ignore" if ignore?

    [ "Record as #{category_label}", counterparty.presence, production&.name ].compact.join(", ")
  end

  def direction_label
    { "any" => "Either way", "in" => "Money in", "out" => "Money out" }.fetch(direction)
  end

  private

  def production_is_ours
    errors.add(:production, "isn't yours") if production && production.organization_id != organization_id
  end
end
