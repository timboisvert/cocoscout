# frozen_string_literal: true

# One answer about one feature of a location or a room (accessibility plan
# §1): yes, no or ask us, with a note. A room with no row inherits the
# location's answer.
class AccessAnswer < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :updated_by, class_name: "User", optional: true

  validates :feature_key, inclusion: { in: AccessFeatures::KEYS }, uniqueness: { scope: %i[owner_type owner_id] }
  validates :answer, inclusion: { in: AccessFeatures::ANSWERS }
  validates :note, length: { maximum: 200 }

  def label = AccessFeatures.label(feature_key)
  def answer_label = AccessFeatures::ANSWER_LABELS.fetch(answer)
end
