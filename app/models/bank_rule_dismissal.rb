# frozen_string_literal: true

# A payee the organization said "it varies, no rule" to (BankSort, the
# Rules page): the payee group's key (BankPayees) as the phrase, and the
# direction, so it is not offered again.
class BankRuleDismissal < ApplicationRecord
  belongs_to :organization
  belongs_to :dismissed_by, class_name: "User", optional: true

  validates :phrase, presence: true
  validates :direction, inclusion: { in: BankRule::DIRECTIONS }
  validates :phrase, uniqueness: { scope: %i[organization_id direction] }
end
