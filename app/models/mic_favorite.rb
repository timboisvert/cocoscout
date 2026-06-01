# frozen_string_literal: true

class MicFavorite < ApplicationRecord
  belongs_to :mic
  belongs_to :user

  validates :user_id, uniqueness: { scope: :mic_id }
end
