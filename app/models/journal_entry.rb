# frozen_string_literal: true

# One balanced posting in an organization's books: its lines always sum to
# zero. Posted entries never change — a correction is a reversing entry
# (LedgerPosting.reverse!), and the only write an entry ever takes after
# posting is the stamp saying it was reversed. That immutability is what makes
# the books trustworthy enough to file taxes from.
class JournalEntry < ApplicationRecord
  belongs_to :organization
  belongs_to :source, polymorphic: true, optional: true
  belongs_to :reversal_of, class_name: "JournalEntry", optional: true
  has_one :reversal, class_name: "JournalEntry", foreign_key: :reversal_of_id, inverse_of: :reversal_of
  has_many :journal_lines, dependent: :restrict_with_exception

  validates :kind, :entry_date, :posted_at, presence: true

  before_update :only_the_reversal_stamp_changes
  before_destroy(prepend: true) { raise ActiveRecord::ReadOnlyRecord, "Journal entries are permanent; post a reversal instead." }

  # The entry currently standing for its source: not reversed, and not itself
  # a reversal.
  scope :live, -> { where(reversed_at: nil, reversal_of_id: nil) }

  def lines_sum_cents
    journal_lines.sum(:amount_cents)
  end

  def balanced?
    journal_lines.any? && lines_sum_cents.zero?
  end

  def reversed?
    reversed_at.present?
  end

  private

  def only_the_reversal_stamp_changes
    allowed = %w[reversed_at updated_at]
    return if (changed - allowed).empty? && reversed_at_was.nil?

    raise ActiveRecord::ReadOnlyRecord, "Journal entries are permanent; post a reversal instead."
  end
end
