# frozen_string_literal: true

# A suggested bank rule (BankRuleSuggestions) the organization said no to:
# the phrase and direction, so it is not suggested again.
class BankRuleDismissal < ApplicationRecord
  belongs_to :organization
  belongs_to :dismissed_by, class_name: "User", optional: true

  validates :phrase, presence: true
  validates :direction, inclusion: { in: BankRule::DIRECTIONS }
  validates :phrase, uniqueness: { scope: %i[organization_id direction] }
end
