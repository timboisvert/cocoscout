# frozen_string_literal: true

# A public edit suggestion against a Mic — anonymous-able (email only)
# or signed-in. Lands in the moderation queue.
class MicSuggestion < ApplicationRecord
  belongs_to :mic
  belongs_to :submitter, class_name: "User", foreign_key: :submitter_user_id, optional: true
  belongs_to :adjudicator, class_name: "User", foreign_key: :adjudicator_user_id, optional: true

  enum :status, { pending: 0, approved: 1, rejected: 2 }, prefix: :status

  validates :submitter_email, presence: true, if: -> { submitter_user_id.blank? }
end
