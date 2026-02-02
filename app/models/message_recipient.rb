class MessageRecipient < ApplicationRecord
  belongs_to :message
  belongs_to :recipient, polymorphic: true  # Person or Group

  validates :message_id, uniqueness: { scope: [ :recipient_type, :recipient_id ] }

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  scope :for_person, ->(person) { where(recipient: person) }
  scope :for_people, ->(people) { where(recipient_type: "Person", recipient_id: people.map(&:id)) }

  def mark_read!
    update!(read_at: Time.current) if read_at.nil?
  end

  def unread?
    read_at.nil?
  end

  def archive!
    update!(archived_at: Time.current) if archived_at.nil?
  end

  def unarchive!
    update!(archived_at: nil)
  end

  def archived?
    archived_at.present?
  end

  # Get the user who owns this recipient (Person → User)
  def user
    case recipient
    when Person then recipient.user
    when Group then nil  # Groups don't have a single user
    end
  end

  # Recipient's display name
  def recipient_name
    recipient&.name || "Unknown"
  end
end
