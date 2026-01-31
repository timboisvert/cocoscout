class MessageBatch < ApplicationRecord
  belongs_to :sender, polymorphic: true
  belongs_to :organization, optional: true
  belongs_to :regarding, polymorphic: true, optional: true

  has_many :messages, dependent: :nullify

  enum :message_type, {
    cast_contact: "cast_contact",
    talent_pool: "talent_pool",
    direct: "direct",
    system: "system"
  }

  validates :subject, presence: true, length: { maximum: 255 }
  validates :message_type, presence: true

  # Get all recipients (People and Groups) from associated messages
  def recipients
    messages.includes(:recipient).map(&:recipient)
  end
end
