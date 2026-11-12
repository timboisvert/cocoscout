# frozen_string_literal: true

# One person's pass through the bank lines waiting (BankSort): what was
# waiting when it started (for the progress band), the rules made, and
# what was skipped. Stopping, or running out of lines, removes it.
class BankSortPass < ApplicationRecord
  belongs_to :organization
  belongs_to :user

  def sorted(waiting) = [ total - waiting, 0 ].max
end
