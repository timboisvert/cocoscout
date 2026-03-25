# frozen_string_literal: true

class FeatureCreditRedemption < ApplicationRecord
  belongs_to :feature_credit
  belongs_to :organization
  belongs_to :redeemable, polymorphic: true

  has_one :course_offering, dependent: :nullify
end
