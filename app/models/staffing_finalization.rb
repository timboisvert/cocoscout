# frozen_string_literal: true

# Records that an org has finalized (and notified staff about) a given week of
# the staffing schedule. A row exists only once a week has been finalized at
# least once; re-finalizing updates finalized_at (the last time staff were
# notified). Until a week is finalized, staff can't see their draft assignments.
class StaffingFinalization < ApplicationRecord
  belongs_to :organization
  belongs_to :finalized_by, class_name: "User", optional: true

  validates :week_start, presence: true,
            uniqueness: { scope: :organization_id }

  scope :finalized, -> { where.not(finalized_at: nil) }

  def finalized?
    finalized_at.present?
  end
end
