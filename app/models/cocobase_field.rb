# frozen_string_literal: true

class CocobaseField < ApplicationRecord
  belongs_to :cocobase

  FIELD_TYPES = %w[text textarea file_upload url yesno].freeze

  serialize :config, coder: JSON

  validates :label, presence: true
  validates :field_type, presence: true, inclusion: { in: FIELD_TYPES }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
