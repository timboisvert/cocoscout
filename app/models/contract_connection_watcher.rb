# frozen_string_literal: true

# Someone the contractor's organization chose to notify as a connected
# contract's tickets sell (LinkedSaleNotices). They can switch it off for
# themself (muted_at) in their own account, and back on.
class ContractConnectionWatcher < ApplicationRecord
  belongs_to :contract_connection
  belongs_to :user
  belongs_to :enabled_by, class_name: "User", optional: true

  validates :user_id, uniqueness: { scope: :contract_connection_id }

  scope :listening, -> { where(muted_at: nil) }

  def muted? = muted_at.present?
end
