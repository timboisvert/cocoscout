class Shoutout < ApplicationRecord
  # Polymorphic association for the recipient (person, group, and future: production, organization)
  belongs_to :shoutee, polymorphic: true

  # The person giving the shoutout
  belongs_to :author, class_name: "Person"

  # Version linking - when a shoutout is updated/replaced
  belongs_to :replaces_shoutout, class_name: "Shoutout", optional: true
  has_one :replacement, class_name: "Shoutout", foreign_key: "replaces_shoutout_id", dependent: :nullify

  # Validations
  validates :content, presence: true, length: { maximum: 2000 }
  validates :shoutee_id, presence: true
  validates :shoutee_type, presence: true
  validates :author_id, presence: true

  # Scopes
  scope :newest_first, -> { order(created_at: :desc) }
  scope :for_entity, ->(entity) { where(shoutee: entity) }
  scope :by_author, ->(author) { where(author: author) }
  scope :current_versions, -> { where(id: left_joins(:replacement).where(replacement: { id: nil }).select(:id)) }

  # Returns a truncated preview of the content
  def preview(length: 150)
    content.truncate(length)
  end

  # Returns all previous versions of this shoutout
  def previous_versions
    versions = []
    current = replaces_shoutout
    while current
      versions << current
      current = current.replaces_shoutout
    end
    versions
  end

  # Check if this shoutout has been replaced
  def replaced?
    replacement.present?
  end

  # Get the latest version of this shoutout
  def latest_version
    replacement&.latest_version || self
  end
end
