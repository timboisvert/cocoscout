# frozen_string_literal: true

# Lightweight tag for the Open Mic Finder (e.g. lgbtq-friendly, first-timer-friendly).
class MicTag < ApplicationRecord
  has_many :mic_taggings, dependent: :destroy
  has_many :mics, through: :mic_taggings

  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/ },
                   length: { maximum: 60 }
  validates :name, presence: true, length: { maximum: 80 }

  def to_param
    slug
  end
end
