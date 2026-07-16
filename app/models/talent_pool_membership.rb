# frozen_string_literal: true

class TalentPoolMembership < ApplicationRecord
  belongs_to :talent_pool, touch: true
  belongs_to :member, polymorphic: true

  validates :talent_pool, presence: true
  validates :member, presence: true
  validates :member_id, uniqueness: { scope: %i[talent_pool_id member_type] }

  # If any production using this pool auto-sends its agreement, request a
  # signature the moment a person joins. Best-effort (see the service) so a
  # messaging hiccup never blocks adding someone.
  after_create_commit :auto_send_agreement, if: -> { member_type == "Person" }

  private

  def auto_send_agreement
    AgreementRequestService.auto_send_for_new_member(talent_pool: talent_pool, person: member)
  end
end
