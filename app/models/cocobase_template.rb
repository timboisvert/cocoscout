# frozen_string_literal: true

class CocobaseTemplate < ApplicationRecord
  belongs_to :production
  has_many :cocobase_template_fields, -> { order(:position) }, dependent: :destroy
  has_many :cocobases, dependent: :nullify

  serialize :event_types, coder: YAML

  validates :default_deadline_days, presence: true,
            numericality: { only_integer: true, greater_than: 0 }

  def matches_event_type?(event_type)
    enabled? && event_types.is_a?(Array) && event_types.include?(event_type.to_s)
  end
end
