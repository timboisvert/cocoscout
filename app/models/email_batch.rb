# frozen_string_literal: true

class EmailBatch < ApplicationRecord
  belongs_to :user
  has_many :email_logs, dependent: :nullify

  validates :subject, presence: true

  scope :recent, -> { order(sent_at: :desc) }

  # Update recipient count based on associated logs
  def update_recipient_count!
    update!(recipient_count: email_logs.count)
  end
end
