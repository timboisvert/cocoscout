class Message < ApplicationRecord
  belongs_to :sender, polymorphic: true  # User or Person
  belongs_to :recipient, polymorphic: true  # Person or Group (NOT User!)
  belongs_to :message_batch, optional: true
  belongs_to :organization, optional: true
  belongs_to :regarding, polymorphic: true, optional: true
  belongs_to :parent, class_name: "Message", optional: true

  has_many :replies, class_name: "Message", foreign_key: :parent_id, dependent: :destroy
  has_rich_text :body

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :active, -> { where(archived_at: nil) }
  scope :top_level, -> { where(parent_id: nil) }
  scope :for_user, ->(user) {
    # Find messages where recipient is any of user's people or groups
    person_ids = user.people.pluck(:id)
    group_ids = user.person&.groups&.pluck(:id) || []

    where(recipient_type: "Person", recipient_id: person_ids)
      .or(where(recipient_type: "Group", recipient_id: group_ids))
  }

  enum :message_type, {
    cast_contact: "cast_contact",    # Manager → cast about a show
    talent_pool: "talent_pool",      # Manager → talent pool members
    direct: "direct",                # Person → person
    system: "system"                 # System notifications
  }

  validates :subject, presence: true, length: { maximum: 255 }
  validates :message_type, presence: true

  def mark_as_read!
    update!(read_at: Time.current) if read_at.nil?
  end

  def unread?
    read_at.nil?
  end

  def reply?
    parent_id.present?
  end

  # Get the User who should see this message
  def recipient_user
    case recipient
    when Person then recipient.user
    when Group then recipient.members.first&.user  # Groups need special handling
    end
  end

  # Human-readable sender name
  def sender_name
    case sender
    when User then sender.person&.name || sender.email_address
    when Person then sender.name
    else "CocoScout"
    end
  end

  # Human-readable recipient name (shows which profile received it)
  def recipient_name
    case recipient
    when Person then recipient.name
    when Group then recipient.name
    else "Unknown"
    end
  end

  # Derive production from regarding object (no separate production column)
  def production
    case regarding
    when Show then regarding.production
    when Production then regarding
    when AuditionCycle then regarding.production
    when SignUpForm then regarding.production
    else nil
    end
  end

  # Context card info based on regarding object
  def regarding_context
    return nil unless regarding

    case regarding
    when Show
      {
        type: :show,
        title: regarding.production.name,
        subtitle: regarding.formatted_date_and_time,
        location: regarding.display_location,
        image: regarding.production.posters.primary.first&.safe_image_variant(:small)
      }
    when Production
      {
        type: :production,
        title: regarding.name,
        image: regarding.logo
      }
    when AuditionCycle
      {
        type: :audition,
        title: regarding.production.name,
        subtitle: "Auditions: #{regarding.name}"
      }
    when SignUpForm
      {
        type: :signup,
        title: regarding.name,
        subtitle: regarding.production.name
      }
    else
      nil
    end
  end
end
