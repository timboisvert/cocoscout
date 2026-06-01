# frozen_string_literal: true

class MicTagging < ApplicationRecord
  belongs_to :mic
  belongs_to :mic_tag

  validates :mic_tag_id, uniqueness: { scope: :mic_id }
end
