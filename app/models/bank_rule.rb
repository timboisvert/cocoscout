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
  belongs_to :show, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  validates :contains, presence: true
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :action, inclusion: { in: ACTIONS }
  validates :direction, inclusion: { in: %w[in out], message: "must be money in or money out to record it" }, if: :record?
  validates :category_key, presence: true, if: :record?
  validate :production_is_ours
  validate :show_is_the_productions

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

  # The lines of a scope this rule fits. The database narrows them to the
  # ones whose description holds a phrase and goes the right way, so a rule
  # never has every line read to it; matches? then has the last word.
  def fitting(lines)
    return [] if phrases.empty?

    lines = lines.where("bank_statement_lines.amount_cents > 0") if direction == "in"
    lines = lines.where("bank_statement_lines.amount_cents < 0") if direction == "out"
    lines.where("bank_statement_lines.description ILIKE ANY (ARRAY[?])", phrases.map { |p| "%#{self.class.sanitize_sql_like(p)}%" }).select { |line| matches?(line) }
  end

  # The lines waiting that this rule fits.
  def waiting_lines
    fitting(organization.bank_statement_lines.to_deal_with)
  end

  def category_label
    return nil unless record?

    MoneyCategories.label_for(category_key, direction == "in" ? :income : :spending, organization: organization)
  end

  # What it does, in words: "Record as Bar purchases, Restaurant Depot" or "Ignore".
  def does
    return "Ignore" if ignore?

    where = production && (show ? "#{production.name} on #{show.date_and_time.strftime('%b %-d, %Y')}" : production.name)
    [ "Record as #{category_label}", counterparty.presence, where ].compact.join(", ")
  end

  def direction_label
    { "any" => "Either way", "in" => "Money in", "out" => "Money out" }.fetch(direction)
  end

  private

  def production_is_ours
    errors.add(:production, "isn't yours") if production && production.organization_id != organization_id
  end

  # A date comes with its production; one from another production is a mistake.
  def show_is_the_productions
    return if show.nil?

    self.production ||= show.production
    errors.add(:show, "is not part of that production") if show.production_id != production&.id
  end
end
