# frozen_string_literal: true

# One person told about one ShowChange, as cast or as staff.
class ShowChangeNotice < ApplicationRecord
  AUDIENCES = %w[cast staff].freeze

  belongs_to :show_change
  belongs_to :person
  belongs_to :sent_by_user, class_name: "User", optional: true

  validates :audience, inclusion: { in: AUDIENCES }
end
